#!/usr/bin/env python3
"""
打包同步脚本 - 根据 pack-config.json 同步游戏资源

用法:
  python3 scripts/sync-pack.py          # 同步到 UrhoX assets/games/
  python3 scripts/sync-pack.py --h5     # 同步到 H5 public/assets/ 并构建 H5 版本
  python3 scripts/sync-pack.py --list   # 仅列出当前配置的游戏
  python3 scripts/sync-pack.py --dry    # 预览操作，不实际执行

工作原理:
  1. 读取 assets/pack-config.json 中的 include 列表
  2. 从 H5 源 (h5mistaryMaker/dist/assets/) 同步选中的游戏到目标目录
  3. 删除目标中不在 include 列表中的游戏目录
  4. 更新 games.json 只包含选中的游戏
"""

import json
import os
import shutil
import sys
import subprocess

# 路径配置
WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_CONFIG = os.path.join(WORKSPACE, "assets", "pack-config.json")
GAMES_JSON_FULL = os.path.join(WORKSPACE, "assets", "games.json")
H5_SOURCE = os.path.join(WORKSPACE, "h5mistaryMaker", "dist", "assets")
URHOX_TARGET = os.path.join(WORKSPACE, "assets", "games")
H5_PROJECT = os.path.join(WORKSPACE, "h5mistaryMaker")
H5_PUBLIC_ASSETS = os.path.join(H5_PROJECT, "public", "assets")


def load_pack_config():
    """加载打包配置"""
    if not os.path.exists(PACK_CONFIG):
        print("ERROR: pack-config.json not found at", PACK_CONFIG)
        sys.exit(1)
    with open(PACK_CONFIG) as f:
        cfg = json.load(f)
    include = cfg.get("include", [])
    if not include:
        print("WARNING: include is empty, will include ALL games")
        # Load full list
        if os.path.exists(GAMES_JSON_FULL):
            with open(GAMES_JSON_FULL) as f:
                all_games = json.load(f)
            include = [g["id"] for g in all_games]
    return include


def load_full_games_json():
    """加载完整 games.json"""
    if not os.path.exists(GAMES_JSON_FULL):
        print("ERROR: games.json not found")
        sys.exit(1)
    with open(GAMES_JSON_FULL) as f:
        return json.load(f)


def get_dir_size_mb(path):
    """获取目录大小 (MB)"""
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not f.endswith('.meta'):
                total += os.path.getsize(fp)
    return total / (1024 * 1024)


def sync_urhox(include, dry=False):
    """同步游戏到 UrhoX assets/games/ 目录"""
    print(f"\n=== UrhoX 同步 ({len(include)} 个游戏) ===\n")

    # 确保目标目录存在
    os.makedirs(URHOX_TARGET, exist_ok=True)

    # 获取当前 assets/games/ 中的目录
    existing = set()
    if os.path.exists(URHOX_TARGET):
        existing = {d for d in os.listdir(URHOX_TARGET)
                    if os.path.isdir(os.path.join(URHOX_TARGET, d))}

    include_set = set(include)
    to_remove = existing - include_set
    to_add = include_set - existing
    to_keep = existing & include_set

    # 删除不需要的
    for game_id in sorted(to_remove):
        target = os.path.join(URHOX_TARGET, game_id)
        size = get_dir_size_mb(target)
        print(f"  [-] 删除: {game_id} ({size:.1f} MB)")
        if not dry:
            shutil.rmtree(target)

    # 复制新增的
    for game_id in sorted(to_add):
        source = os.path.join(H5_SOURCE, game_id)
        target = os.path.join(URHOX_TARGET, game_id)
        if not os.path.exists(source):
            print(f"  [!] 源不存在: {source}")
            continue
        size = get_dir_size_mb(source)
        print(f"  [+] 添加: {game_id} ({size:.1f} MB)")
        if not dry:
            shutil.copytree(source, target)

    # 保留的
    for game_id in sorted(to_keep):
        print(f"  [=] 保留: {game_id}")

    # 更新 games.json（过滤版）
    all_games = load_full_games_json()
    filtered = [g for g in all_games if g["id"] in include_set]
    # 按 include 顺序排序
    id_order = {gid: i for i, gid in enumerate(include)}
    filtered.sort(key=lambda g: id_order.get(g["id"], 999))

    if not dry:
        with open(GAMES_JSON_FULL, "w") as f:
            json.dump(filtered, f, ensure_ascii=False, indent=2)
        print(f"\n  games.json 已更新: {len(filtered)} 个游戏")

    # 统计总大小
    if not dry and os.path.exists(URHOX_TARGET):
        total = get_dir_size_mb(URHOX_TARGET)
        print(f"\n  总大小: {total:.1f} MB")


def sync_h5(include, dry=False):
    """同步游戏到 H5 并构建"""
    print(f"\n=== H5 打包 ({len(include)} 个游戏) ===\n")

    if not os.path.exists(H5_PROJECT):
        print("ERROR: H5 project not found at", H5_PROJECT)
        sys.exit(1)

    h5_games_json = os.path.join(H5_PUBLIC_ASSETS, "games.json")
    if not os.path.exists(h5_games_json):
        print(f"WARNING: {h5_games_json} not found, looking in dist/")
        h5_games_json = os.path.join(H5_SOURCE, "..", "games.json")

    # H5 的 build-single.cjs 思路: 临时移走不需要的游戏目录
    # 这里改为: 直接修改 games.json 过滤 → vite build → 恢复
    # 但 vite 会把 public/assets/ 全部拷贝到 dist/
    # 所以需要临时移走不需要的游戏目录

    include_set = set(include)
    hold_dir = os.path.join(H5_PROJECT, ".games-hold")

    # 找到 H5 的 assets 源目录
    h5_assets = H5_PUBLIC_ASSETS
    if not os.path.exists(h5_assets):
        h5_assets = H5_SOURCE
        print(f"  Using dist/assets as source: {h5_assets}")

    all_dirs = [d for d in os.listdir(h5_assets)
                if os.path.isdir(os.path.join(h5_assets, d))]
    to_hold = [d for d in all_dirs if d not in include_set]

    print(f"  保留: {len(include)} 个游戏目录")
    print(f"  临时移出: {len(to_hold)} 个游戏目录")

    if dry:
        print("\n  (dry run, 跳过实际构建)")
        return

    # 1. 备份 games.json
    games_json_path = os.path.join(h5_assets, "games.json")
    games_backup = None
    if os.path.exists(games_json_path):
        with open(games_json_path) as f:
            games_backup = f.read()
        # 过滤
        all_data = json.loads(games_backup)
        if isinstance(all_data, list):
            filtered = [g for g in all_data if g.get("id") in include_set]
        elif isinstance(all_data, dict) and "games" in all_data:
            all_data["games"] = [g for g in all_data["games"] if g.get("id") in include_set]
            filtered = all_data
        else:
            filtered = all_data
        with open(games_json_path, "w") as f:
            json.dump(filtered, f, ensure_ascii=False, indent=2)

    # 2. 移走不需要的目录
    os.makedirs(hold_dir, exist_ok=True)
    for d in to_hold:
        src = os.path.join(h5_assets, d)
        dst = os.path.join(hold_dir, d)
        if os.path.exists(src):
            shutil.move(src, dst)

    try:
        # 3. 执行 vite build
        print("\n  执行 vite build...")
        subprocess.run(
            ["npx", "vite", "build"],
            cwd=H5_PROJECT,
            check=True,
            env={**os.environ, "http_proxy": "http://127.0.0.1:1080", "https_proxy": "http://127.0.0.1:1080"}
        )
        print("\n  H5 构建成功!")

        # 计算 dist 大小
        dist_dir = os.path.join(H5_PROJECT, "dist")
        if os.path.exists(dist_dir):
            total = get_dir_size_mb(dist_dir)
            print(f"  dist/ 总大小: {total:.1f} MB")

    except Exception as e:
        print(f"\n  构建失败: {e}")
    finally:
        # 4. 恢复移走的目录
        for d in to_hold:
            src = os.path.join(hold_dir, d)
            dst = os.path.join(h5_assets, d)
            if os.path.exists(src):
                shutil.move(src, dst)
        try:
            os.rmdir(hold_dir)
        except:
            pass

        # 5. 恢复 games.json
        if games_backup and os.path.exists(games_json_path):
            with open(games_json_path, "w") as f:
                f.write(games_backup)

    print("\n  源目录已恢复原状")


def main():
    args = sys.argv[1:]

    if "--list" in args:
        include = load_pack_config()
        all_games = load_full_games_json()
        game_map = {g["id"]: g["name"] for g in all_games}
        print(f"当前打包配置 ({len(include)} 个游戏):\n")
        for gid in include:
            name = game_map.get(gid, "???")
            print(f"  {gid:30s} {name}")
        return

    dry = "--dry" in args
    include = load_pack_config()

    if "--h5" in args:
        sync_h5(include, dry=dry)
    else:
        sync_urhox(include, dry=dry)

    if not dry:
        print("\n✅ 完成!")


if __name__ == "__main__":
    main()
