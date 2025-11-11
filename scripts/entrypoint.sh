#!/bin/bash

# 统一入口脚本，支持调用tdx2db和ko_trading的Python脚本

set -e

# 显示帮助信息
show_help() {
    cat << EOF
统一入口脚本，支持以下命令：

tdx2db命令：
    tdx2db [args]           - 执行tdx2db Go程序
    tdx2db init             - 初始化数据库
    tdx2db cron             - 执行增量更新

ko_trading命令：
    run_csindex_and_shenwan_industry_update - 更新中证指数成分股和申万行业分类数据

其他：
    help                    - 显示此帮助信息

示例：
    $0 tdx2db init
    $0 tdx2db cron
    $0 run_csindex_and_shenwan_industry_update
EOF
}

# 检查是否有参数
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# 解析第一个参数
case "$1" in
    "tdx2db")
        shift  # 移除tdx2db参数
        exec /tdx2db "$@"
        ;;
    "run_csindex_and_shenwan_industry_update")
        cd /opt/ko_trading
        exec python3 cron.py
        ;;
    "help"|"-h"|"--help")
        show_help
        exit 0
        ;;
    *)
        echo "错误: 未知命令 '$1'"
        echo
        show_help
        exit 1
        ;;
esac