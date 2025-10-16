#!/bin/bash

#######################################
# 文件名: launch_frida.sh
# 描述: Frida 开发调试脚本，一键化完成调试和日志输出，支持逆向团队开发调试/支持算法同学做算法调试
# 功能:
#   - 支持USB连接设备
#   - 支持指定目标进程(PID或进程名)
#   - 支持指定JS脚本
#   - 支持PC端或Android端运行环境
#   - 支持日志输出重定向
#   - 支持JS脚本参数传递
#   - 支持自定义工作目录
#   - 支持自定义frida-server文件
#   - 支持关闭所有frida相关进程
#   - 支持日志pull功能 (待更新)
# 作者: [wuyou]
# 创建时间: [2025-05-20]
# 修改时间: [2025-05-20]
# 版本: 1.0.0
#
# 使用示例:
# android 运行
# ./launch_frida.sh -U -n vendor.qti.camera.provider-service_64 -e android -j hookEV0Sensitivites.js -o hookEV0BasicCal_NoPeople_111.txt
# pc运行
# ./launch_frida.sh -U -n vendor.qti.camera.provider-service_64  -j hookEV0Sensitivites.js -o hookEV0BasicCal_people333.txt
#######################################


# 定义日志输出函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [Line $1] $2"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [Line $1] $2"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [Line $1] $2"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] [Line $1] $2"
}

log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] [Line $1] $2"
}

# 定义分隔线函数
print_separator() {
    echo "=================================================="
}


# 定义帮助函数
show_help() {
    echo "用法: $0 [选项]"
    echo "必选项:"
    echo "  -U                使用USB连接设备"
    echo "  -j <js_script>    指定js脚本"
    echo
    echo "进程指定选项(二选一):"
    echo "  -p <pid>          指定目标进程PID"
    echo "  -n <process_name> 指定目标进程名称"
    echo
    echo "可选项:"
    echo "  -e <environment>  指定sh脚本运行环境 (pc 或 android), 默认 pc"
    echo "  -o <output_file>  指定输出日志文件"
    echo "  -P <params>       为JS脚本指定参数"
    echo "  -W <dirPath>      指定工作目录       (默认/data/local/tmp/frida_mi/)"
    echo "  -f <frida-server> 指定frida-server文件 (默认frida-server-16.7.0-android-arm64)"
    echo "  -k                关闭所有frida相关进程"
    echo "  -h, --help        显示此帮助信息"
    echo "  -pull [path]       将手机中的日志文件pull到本地"
    echo "                     path可以是文件或目录,默认是/data/bbklog/camera_log"
    echo
    echo "示例:"
    echo "  $0 -U -n camerahalserver -j 0_test_launch_frida.js (日志输出在终端,pc端运行)"
    echo "  $0 -U -n camerahalserver -j 0_test_launch_frida.js -e android -o textLog.txt (日志重定向到文件,android端运行)"
    echo "  $0 -U -p 25176 -j 2_test_rpc_frida.js -e android -P '{"test":11,"test1":22}' -o 333.txt (传入param,日志重定向到文件,android端运行)"
    echo "  $0 -U -p 25176 -j 2_test_rpc_frida.js -e pc -P '{"test":11,"test1":22}' -o 333.txt (传入param,日志重定向到文件,pc端运行)"
    echo "  $0 -U -n camerahalserver -j 2_test_rpc_frida.js -e pc -P '{"test":11,"test1":22}'"
    echo "  $0 -U -p 25176 -j 2_test_rpc_frida.js -e pc -P '{"test":11,"test1":22}' -o 333.txt -f frida-server-16.7.0-android-arm64_test (指定frida-server文件,pc端运行)"
    echo "  $0 -k (关闭frida相关进程)"
    echo "  $0 -pull (pull默认目录 /data/bbklog/camera_log)"
    echo "  $0 -pull /data/local/tmp/frida_mi/logs/ (pull指定目录)"
    echo "  $0 -pull /data/local/tmp/frida_mi/logs/test.log (pull单个文件)"
}

# 初始化变量
USB_CONNECT=false  # USB连接设备
PROCESS_PID=""  # 目标进程PID
PROCESS_NAME=""  # 目标进程名称
LOG_FILE=""  # 日志文件
JS_PARAMS=""  # JS脚本参数
RUN_ENV="pc" # 默认运行环境为pc
JS_SCRIPT="" # JS脚本
WORK_PATH="/data/local/tmp/frida_mi" #工作目录(默认/data/local/tmp/frida_mi/)
FRIDA_SERVER="frida-server-16.7.0-android-arm64" # frida-server文件(默认frida-server-16.7.0-android-arm64)
KILL_ALL=false # 是否关闭所有frida进程
PULL_PATH=""  # 默认pull路径
PULL_ENABLED=false  # 是否启用pull功能
DUMP_ENABLED=false  # 是否启用dump功能
CLEAR_ENABLED=false  # 是否启用clear功能

# 需要 dump 和 clear 的目录
DUMP_SRC=(
    "/data/vendor/camera/gtr"
    "/data/vendor/camera/dump/*/beauty"
    "/data/misc/camera"
    "/data/local/tmp/beauty_GTR"
)
CLEAR_SRC=(
    "/data/vendor/camera/gtr"
    "/data/vendor/camera/dump"
    "/data/misc/camera"
    "/data/local/tmp/beauty_GTR"
)

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k)
            KILL_ALL=true
            shift
            ;;
        -pull)
            PULL_ENABLED=true
            if [ ! -z "$2" ] && [[ ! "$2" =~ ^- ]]; then # 如果第二个参数有值且不是以-开头,则认为第二个参数是pull路径
                PULL_PATH="$2"
                log_info $LINENO "pull_path_custom: $PULL_PATH"
                shift 2
            else  # 执行默认的pull功能
                log_info $LINENO "pull_path: $PULL_PATH"
                shift
            fi

            ;;
        -dump)
            DUMP_ENABLED=true
            shift
            ;;
        -clear)
            CLEAR_ENABLED=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [ "$KILL_ALL" = true ]; then
                log_error $LINENO "错误: -k 选项不能与其他选项一起使用"
                show_help
                exit 1
            fi
            if [ "$PULL_ENABLED" = true ]; then
                log_error $LINENO "错误: -pull 选项不能与其他选项一起使用"
                show_help
                exit 1
            fi
            case "$1" in
                -U)
                    USB_CONNECT=true  # USB连接设备
                    shift
                    ;;
                -p)
                    PROCESS_PID="$2" # 目标进程PID
                    shift 2
                    ;;
                -n)
                    PROCESS_NAME="$2" # 目标进程名称
                    shift 2
                    ;;
                -j)
                    JS_SCRIPT="$2" # JS脚本
                    shift 2
                    ;;
                -e)
                    RUN_ENV="$2"  # 指定脚本运行环境
                    shift 2
                    ;;
                -o)
                    LOG_FILE="$2" # 指定输出文件
                    shift 2
                    ;;
                -P)
                    JS_PARAMS="$2" # JS脚本参数
                    shift 2
                    ;;
                -W)
                    WORK_PATH="$2" # 指定工作目录
                    shift 2
                    ;;
                -f)
                    FRIDA_SERVER="$2" # 指定frida-server文件
                    shift 2
                    ;;
                *)
                    echo "错误: 未知选项 $1"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
    esac
done

# 如果指定了-k选项，则关闭所有frida相关进程并退出
if [ "$KILL_ALL" = true ]; then
    print_separator
    log_info $LINENO "正在关闭所有frida相关进程..."
    
    # 关闭frida-server进程
    log_info $LINENO "正在关闭frida-server进程..."
    adb shell "su -c 'pkill -f frida-server'"
    if [ $? -eq 0 ]; then
        log_success $LINENO "frida-server进程已关闭"
    else
        log_warn $LINENO "没有找到frida-server进程"
    fi
    
    # 关闭frida-inject进程
    log_info $LINENO "正在关闭frida-inject进程..."
    adb shell "su -c 'pkill -f frida-inject'"
    if [ $? -eq 0 ]; then
        log_success $LINENO "frida-inject进程已关闭"
    else
        log_warn $LINENO "没有找到frida-inject进程"
    fi
    
    # 关闭其他可能的frida相关进程
    log_info $LINENO "正在关闭其他frida相关进程..."
    adb shell "su -c 'pkill -f frida'"
    if [ $? -eq 0 ]; then
        log_success $LINENO "其他frida相关进程已关闭"
    else
        log_warn $LINENO "没有找到其他frida相关进程"
    fi
    
    print_separator
    log_success $LINENO "所有frida相关进程已关闭"
    exit 0
fi

# 验证必要参数（仅在非-k和非-pull选项时验证）
if [ "$KILL_ALL" = false ] && [ "$PULL_ENABLED" = false ] && [ "$DUMP_ENABLED" = false ] && [ "$CLEAR_ENABLED" = false ]; then
    if [ -z "$USB_CONNECT" ]; then
        log_error $LINENO "必须指定USB连接 (-U 选项)"
        show_help
        exit 1
    fi

    # 验证进程参数 (-p 或 -n 至少需要一个)
    if [ -z "$PROCESS_PID" ] && [ -z "$PROCESS_NAME" ]; then
        log_error $LINENO "必须指定目标进程的PID (-p 选项)或进程名称 (-n 选项)"
        show_help
        exit 1
    fi
    
    if [ -z "$JS_SCRIPT" ]; then
        log_error $LINENO "必须指定JS脚本 (-j 选项)"
        show_help
        exit 1
    fi
fi


# dump_all 功能函数
dump_all() {
    # 获取当前时间戳
    TS=$(date +"%Y%m%d_%H%M%S")
    DUMP_DIR="frida_dump_${TS}"

    # 创建本地目标目录
    mkdir -p "$DUMP_DIR"

    for SRC in "${DUMP_SRC[@]}"; do
        # 处理通配符
        adb shell su -c "ls -d $SRC 2>/dev/null" | while read REMOTE_DIR; do
            if [ -n "$REMOTE_DIR" ]; then
                LOCAL_SUBDIR="$DUMP_DIR${REMOTE_DIR}"
                mkdir -p "$LOCAL_SUBDIR"
                echo "正在拉取: $REMOTE_DIR"
                adb shell su -c "ls -A \"$REMOTE_DIR\"" | while read FILE; do
                    if [ -n "$FILE" ]; then
                        adb pull "$REMOTE_DIR/$FILE" "$LOCAL_SUBDIR/" >/dev/null
                    fi
                done
            fi
        done
    done

    echo "Dump 完成，文件夹: $DUMP_DIR"
}

# clear_all 功能函数
clear_all() {

    for SRC in "${CLEAR_SRC[@]}"; do
        # 处理 /data/misc/camera 专用规则（仅清空子目录及内容，保留根目录 txt 等文件）
        if [ "$SRC" = "/data/misc/camera" ]; then
            adb shell su -c "
for dir in \$(ls -d $SRC/*/ 2>/dev/null); do
    echo 清空目录: \$dir
    rm -rf \"\$dir\"/*
done"
            echo "清理 $SRC 完成"
        else
            adb shell su -c "
if [ -d \"$SRC\" ]; then
    echo 清空目录: $SRC
    rm -rf \"$SRC\"/*
else
    echo 目录不存在: $SRC
fi
"
            echo "清理 $SRC 完成"
        fi
    done
    echo "全部清理完成"
}

# 添加pull功能函数
pull_logs() {
    local pull_path_custom="$1"
    print_separator
    log_info $LINENO "开始pull日志文件..."
    log_info $LINENO "pull_path_custom 参数1: $1"
    log_info $LINENO "pull_path_custom: $pull_path_custom"

    # 检查pull_path_custom是否有值
    if [ -z "$pull_path_custom" ]; then
        log_error $LINENO "未指定要pull的路径"
        log_info $LINENO "使用默认路径: /data/bbklog/camera_log"
        pull_path_custom="/data/bbklog/camera_log"

        # 确保本地目标目录存在，使用当前日期和时分作为目录名
        current_datetime=$(date '+%Y%m%d_%H%M')
        mkdir -p "./log_${current_datetime}"

        # 清理设备上已存在的临时目录
        log_info $LINENO "正在清理设备上已存在的 /data/local/tmp/camera_log ..."
        adb shell "rm -rf /data/local/tmp/camera_log"

        # 将设备上的日志目录复制到临时位置 (/data/local/tmp)
        log_info $LINENO "正在将 /data/bbklog/camera_log 复制到 /data/local/tmp/ ..."
        adb shell "su -c 'chmod -R 777 /data/bbklog/camera_log/'"
        adb shell "su -c 'cp -r /data/bbklog/camera_log /data/local/tmp/'"

        # 确保临时目录中的文件具有读取权限
        log_info $LINENO "正在设置 /data/local/tmp/camera_log 的权限 ..."
        adb shell "su -c 'chmod -R 777 /data/local/tmp/camera_log'"

        # /data/local/tmp/camera_log 合并成一个log
        log_info $LINENO "正在合并 /data/local/tmp/camera_log 目录下的所有log文件..."
        adb shell "su -c 'cat /data/local/tmp/camera_log/cam_log_202* /data/local/tmp/camera_log/cam_log_0.txt > /data/local/tmp/camera_log/camera_all_log.log'"

        # 从临时位置拉取日志目录到本地
        log_info $LINENO "正在从 /data/local/tmp/camera_log 拉取日志到 ./log_${current_datetime} ..."
        adb pull /data/local/tmp/camera_log/camera_all_log.log ./log_${current_datetime}/
    else
        log_info $LINENO "将从路径 $pull_path_custom 拉取日志"
        # 判断 pull_path 是否是 .txt 或者 .log 文件
        if [ "${pull_path_custom##*.}" = "txt" ] || [ "${pull_path_custom##*.}" = "log" ]; then
            log_info $LINENO "pull_path_custom 是 .txt 或者 .log 文件"
            # 如果是文件，直接pull
            adb pull "$pull_path_custom" ./
        else
            log_info $LINENO "pull_path 是目录"
            # 获取目录中所有的文件
            log_info $LINENO "正在pull目录 $pull_path_custom 中的所有文件..."

            # 确保本地目标目录存在，使用当前日期和时分作为目录名
            current_datetime=$(date '+%Y%m%d_%H%M')
            mkdir -p "./log_${current_datetime}"

            # 清理设备上已存在的临时目录
            log_info $LINENO "正在清理设备上已存在的 /data/local/tmp/log_yourself ..."
            adb shell "rm -rf /data/local/tmp/log_yourself"

            # 将设备上的日志目录复制到临时位置 (/data/local/tmp)
            log_info $LINENO "正在将 $pull_path_custom 复制到 /data/local/tmp/ ..."
            adb shell "su -c 'chmod -R 777 $pull_path_custom/'"
            adb shell "su -c 'cp -r $pull_path_custom /data/local/tmp/log_yourself'"

            # 确保临时目录中的文件具有读取权限
            log_info $LINENO "正在设置 /data/local/tmp/log_yourself 的权限 ..."
            adb shell "su -c 'chmod -R 777 /data/local/tmp/log_yourself'"

            #  /data/local/tmp/log_yourself 合并成一个log
            log_info $LINENO "正在合并 /data/local/tmp/log_yourself 目录下的所有log文件..."
            adb shell "su -c 'cat /data/local/tmp/log_yourself/cam_log_202* /data/local/tmp/log_yourself/cam_log_0.txt > /data/local/tmp/log_yourself/camera_all_log.log'"

            # 从临时位置拉取日志目录到本地
            log_info $LINENO "正在从 /data/local/tmp/log_yourself/camera_all_log.log 拉取日志到 ./log_${current_datetime}/ ..."
            adb pull /data/local/tmp/log_yourself/camera_all_log.log ./log_${current_datetime}/

            # # 重命名本地日志文件扩展名
            # log_info $LINENO "正在将 ./log_${current_datetime} 目录下的 .txt 文件重命名为 .log ..."
            # find ./log_${current_datetime} -type f -name '*.txt' -print0 | while IFS= read -r -d $'\0' file; do
            #     mv -- "$file" "${file%.txt}.log"
            # done

            # # 为没有扩展名的文件添加 .log 后缀
            # log_info $LINENO "正在为 ./log_${current_datetime} 目录下没有扩展名的文件添加 .log 后缀 ..."
            # find ./log_${current_datetime} -type f -not -name '*.*' -print0 | while IFS= read -r -d $'\0' file; do
            #     mv -- "$file" "$file.log"
            # done
            
            # log_info $LINENO "日志拉取和重命名完成"
            # cat ./log_${current_datetime}/log_yourself/cam_log_202* ./log_${current_datetime}/log_yourself/cam_log_0.log > ./log_${current_datetime}/log_yourself/wy_all_cam_log.log
            # log_info $LINENO "合并日志完成"

            # 下载dump
            adb pull /data/vendor/camera/dump ./log_${current_datetime}/
        fi
    fi
}


# 在主逻辑开始处添加pull功能的调用
if [ "$PULL_ENABLED" = true ]; then

    if [ -z "$PULL_PATH" ]; then
        pull_logs  # 执行默认的pull功能
    else  # 执行自定义的pull功能
        PULL_PATH_custom="$PULL_PATH"
        log_info $LINENO "PULL_PATH_custom: $PULL_PATH_custom"
        pull_logs "$PULL_PATH_custom"
    fi
    exit 0
fi

# dump_all 功能 执行dump_all 功能
if [ "$DUMP_ENABLED" = true ]; then
    dump_all
    exit 0
fi

# clear_all 功能
if [ "$CLEAR_ENABLED" = true ]; then
    clear_all
    exit 0
fi

print_separator
log_info $LINENO "检测到Windows环境,获取frida版本..."
# Windows环境下获取frida版本
frida_version=$(frida --version 2>/dev/null)
if [ -z "$frida_version" ]; then
    log_warn $LINENO "无法获取frida版本,请确保frida已正确安装"
    frida_version="未知"
else
    log_info $LINENO "Windows环境下frida版本: $frida_version"
fi

# 判断手机中的/data/local/tmp/frida/是否存在
log_info $LINENO "检查手机中的frida目录..."
frida_dir_exists=$(adb shell "test -d $WORK_PATH")
if [ "$frida_dir_exists" = "1" ]; then
    log_success $LINENO "手机中的 $WORK_PATH 目录已存在"
else
    log_warn $LINENO "手机中的 $WORK_PATH 目录不存在，正在创建..."
    adb shell "mkdir -p $WORK_PATH"
    if [ $? -eq 0 ]; then
        log_success $LINENO "$WORK_PATH 目录创建成功"
    else
        log_error $LINENO "$WORK_PATH 目录创建失败"
        exit 1
    fi
fi

# 将 WORK_PATH 设置为/data/local/tmp/frida_test/
#WORK_PATH="/data/local/tmp/frida_test/"

# 检查手机中是否已存在frida-server文件
print_separator
log_info $LINENO "检查手机中是否已存在frida-server文件..."
frida_server_exists=$(adb shell "test -f $WORK_PATH/$FRIDA_SERVER && echo 1 || echo 0")
if [ "$frida_server_exists" = "1" ]; then
    log_success $LINENO "$FRIDA_SERVER 文件已存在,无需上传"
else
    # 上传frida-server文件到手机
    log_info $LINENO "正在上传$FRIDA_SERVER 文件到手机..."
    adb push $FRIDA_SERVER $WORK_PATH
    if [ $? -eq 0 ]; then
        log_success $LINENO "$FRIDA_SERVER 上传成功"
        log_info $LINENO "正在赋予文件可执行权限..."
        adb shell "su -c 'chmod +x $WORK_PATH/$FRIDA_SERVER'"
        if [ $? -eq 0 ]; then
            log_success $LINENO "权限设置成功"
        else
            log_error $LINENO "权限设置失败"
            exit 1
        fi
    else
        log_error $LINENO "$FRIDA_SERVER 上传失败"
        exit 1
    fi
fi

# 检查手机中是否已存在frida-inject文件
print_separator
log_info $LINENO "检查手机中是否已存在frida-inject文件..."
frida_inject_exists=$(adb shell "test -f $WORK_PATH/frida-inject && echo 1 || echo 0")
if [ "$frida_inject_exists" = "1" ]; then
    log_success $LINENO "frida-inject文件已存在,无需上传"
else
    # 上传frida-inject文件到手机
    log_info $LINENO "正在上传frida-inject文件到手机..."
    adb push frida-inject $WORK_PATH
    if [ $? -eq 0 ]; then
        log_success $LINENO "frida-inject上传成功"
        log_info $LINENO "正在赋予文件可执行权限..."
        adb shell "su -c 'chmod +x $WORK_PATH/frida-inject'"
        if [ $? -eq 0 ]; then
            log_success $LINENO "权限设置成功"
        else
            log_error $LINENO "权限设置失败"
            exit 1
        fi
    else
        log_error $LINENO "frida-inject上传失败"
        exit 1
    fi
fi

# 上传JS脚本到手机
print_separator
log_info $LINENO "正在上传JS脚本到手机..."
if [ -f "$JS_SCRIPT" ]; then
    adb push "$JS_SCRIPT" "$WORK_PATH"
    if [ $? -eq 0 ]; then
        log_success $LINENO "$JS_SCRIPT 脚本上传成功"
    else
        log_error $LINENO "JS脚本上传失败"
        exit 1  
    fi
else
    log_error $LINENO "JS脚本文件 $JS_SCRIPT 不存在"
    exit 1
fi

# 检查frida-server是否已经在运行
print_separator
log_info $LINENO "检查frida-server是否已经在运行..."
sleep 1   # 等待1s 必须加，不然第一次跑脚本会失败
FRIDA_RUNNING=$(adb shell "ps -ef | grep frida-server | grep -v grep | awk '{print \$2}'")
log_debug $LINENO "FRIDA_RUNNING: $FRIDA_RUNNING"
if [ -z "$FRIDA_RUNNING" ]; then
    log_info $LINENO "frida-server未运行,正在启动..."
    # 在后台启动frida-server，使用su -c获取root权限
    log_info $LINENO "执行命令: adb shell 'su -c '$WORK_PATH/$FRIDA_SERVER > /dev/null 2>&1 &'"
    adb shell "su -c 'nohup $WORK_PATH/$FRIDA_SERVER > /dev/null 2>&1 &'"
    # 等待frida-server启动
    sleep 1
    # 再次检查是否成功启动
    FRIDA_RUNNING1=$(adb shell "ps -ef | grep frida-server | grep -v grep | awk '{print \$2}'|head -n 1")
    log_debug $LINENO "FRIDA_RUNNING1: $FRIDA_RUNNING1"
    if [ -z "$FRIDA_RUNNING1" ]; then
        log_error $LINENO "frida-server启动失败,请检查："
        log_error $LINENO "1. 设备是否已root"
        log_error $LINENO "2. frida-server是否有执行权限"
        log_error $LINENO "3. frida-server版本是否与设备架构匹配"
        exit 1
    else
        log_success $LINENO "frida-server启动成功"
    fi
else
    log_success $LINENO "frida-server已经在运行中"
fi



# 检查进程PID或进程名称
print_separator
log_info $LINENO "正在检查目标进程..."
if [ ! -z "$PROCESS_PID" ]; then
    log_info $LINENO "使用指定的进程PID: $PROCESS_PID"
    TARGET_PID=$PROCESS_PID
elif [ ! -z "$PROCESS_NAME" ]; then
    log_info $LINENO "使用指定的进程名称: $PROCESS_NAME"
    # 获取进程PID
    GET_PROCESS_PID=$(adb shell "ps -ef | grep $PROCESS_NAME | grep -v grep | awk '{print \$2}'")
    if [ -z "$GET_PROCESS_PID" ]; then
        log_error $LINENO "未找到名为 $PROCESS_NAME 的进程"
        exit 1
    fi
    TARGET_PID=$GET_PROCESS_PID
    log_info $LINENO "找到进程 $PROCESS_NAME 的PID: $TARGET_PID"
else
    log_error $LINENO "未指定进程PID或进程名称"
    log_error $LINENO "请使用 PROCESS_PID 或 PROCESS_NAME 参数"
    exit 1
fi


# js 脚本在windows环境下运行        
if [ "$RUN_ENV" = "pc" ]; then
    print_separator
    log_info $LINENO "js 脚本在pc环境下运行"
    # frida -p $(adb shell pidof camerahalserver) -l ./test.js -U -o mergeresult01.txt -P '{"key":"value"}'
    # 检查是否有-P参数
    if [ ! -z "$JS_PARAMS" ]; then
        log_info $LINENO "有JS_PARAMS参数: $JS_PARAMS"
        # 检查是否有-o参数
        if [ -z "$LOG_FILE" ]; then
            log_info $LINENO "未指定输出文件，输出将显示在控制台"
            # 如果没有指定输出文件，则不使用-o参数
            log_debug $LINENO "执行命令: frida -U -p $TARGET_PID -l $JS_SCRIPT --parameters \"$JS_PARAMS\""
            frida -U -p $TARGET_PID -l $JS_SCRIPT -U --parameters "$JS_PARAMS"
        else
            # 有-o参数
            log_info $LINENO "执行命令: frida -U -p $TARGET_PID -l $JS_SCRIPT --parameters \"$JS_PARAMS\" -o $LOG_FILE"
            frida -U -p $TARGET_PID -l $JS_SCRIPT -U --parameters "$JS_PARAMS" -o $LOG_FILE
        fi
    else
        # 没有-P参数，使用默认命令
        log_info $LINENO "没有JS_PARAMS参数"
        # 检查是否有-o参数
        if [ -z "$LOG_FILE" ]; then
            log_info $LINENO "未指定输出文件，输出将显示在控制台"
            # 如果没有指定输出文件，则不使用-o参数
            log_debug $LINENO "执行命令: frida -U -p $TARGET_PID -l $JS_SCRIPT -U"
            frida -U -p $TARGET_PID -l $JS_SCRIPT -U
        else
            log_info $LINENO "重定向到文件$LOG_FILE"
            log_debug $LINENO "执行命令: frida -U -p $TARGET_PID -l $JS_SCRIPT -U -o $LOG_FILE"
            frida -U -p $TARGET_PID -l $JS_SCRIPT -U -o $LOG_FILE 
        fi
    fi
# js脚本在android环境下运行
elif [ "$RUN_ENV" = "android" ]; then
    print_separator
    log_info $LINENO "js脚本在android环境下运行"
    # /data/local/tmp/frida-inject -p `pidof vendor.vivo.hardware.camera3rd.provider@1.0-service` -s /data/local/tmp/bypass_hdr.js -P "{\"enableBypassing\":true, \"enableFakeImg\":true, \"fakeHdrImg\": \"$1\", \"fakeXdrGainImg\": \"$2\"}" 

    # 检查frida-inject进程 是否运行
    FRIDA_INJECT_RUNNING=$(adb shell "ps -ef | grep frida-inject | grep -v grep | awk '{print \$2}'")
    if [ -z "$FRIDA_INJECT_RUNNING" ]; then
        log_success $LINENO "frida-inject进程未运行"
    else
        log_success $LINENO "frida-inject进程已运行"
        # 杀死frida-inject有关进程
        # kill -9 $(pgrep -f "frida-inject -p 9006")
        log_info $LINENO "正在杀死frida-inject相关进程..."
        adb shell "su -c 'kill -9 \$(pgrep -f \"frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT\")'"
        adb shell "su -c 'pkill -f \"frida-inject -p $TARGET_PID\"'"
        adb shell "su -c 'pkill -f \"sh -c.*frida-inject -p $TARGET_PID\"'"
    fi
    print_separator
    # 检查是否有-P参数
    if [ ! -z "$JS_PARAMS" ]; then
        log_info $LINENO "有JS_PARAMS参数 : $JS_PARAMS"
        # 对JS_PARAMS进行转义处理
        JS_PARAMS=$(echo "$JS_PARAMS" | sed 's/"/\\"/g')
        log_debug $LINENO "转义后的参数: $JS_PARAMS"
        #检查是否有-o参数
        if [ -z "$LOG_FILE" ]; then
            log_warn $LINENO "未指定输出文件，输出将显示在控制台"
            # 如果没有指定输出文件，则不使用-o参数
            log_debug $LINENO "执行命令: adb shell 'su -c \"$WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT -P "$JS_PARAMS"\""
            adb shell "su -c '$WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT -P "$JS_PARAMS"'"
        else
            log_info $LINENO "输出到文件$LOG_FILE"
            log_info $LINENO "执行命令: adb shell 'su -c \"nohup $WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT -P "$JS_PARAMS" > $WORK_PATH/$LOG_FILE 2>&1 &\"'"
            adb shell "su -c 'nohup $WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT -P "$JS_PARAMS" > $WORK_PATH/$LOG_FILE 2>&1 &'"
        fi
    else
        log_info $LINENO "没有JS_PARAMS参数"
        #检查是否有-o参数
        if [ -z "$LOG_FILE" ]; then
            log_warn $LINENO "未指定输出文件，输出将显示在控制台"
            # 如果没有指定输出文件，则不使用-o参数
            log_debug $LINENO "执行命令: adb shell 'su -c \"$WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT\""
            adb shell "su -c '$WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT'"
        else
            log_info $LINENO "输出到文件$LOG_FILE"
            log_info $LINENO "后台运行frida-inject并输出到文件$LOG_FILE"
            log_info $LINENO "执行命令: adb shell 'su -c \"nohup $WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT > $WORK_PATH/$LOG_FILE 2>&1 &\"'"
            adb shell "su -c 'nohup $WORK_PATH/frida-inject -p $TARGET_PID -s $WORK_PATH/$JS_SCRIPT > $WORK_PATH/$LOG_FILE 2>&1 &'"
        fi
    fi
else
    log_error $LINENO "未指定运行环境 -e pc 或 -e android"
    exit 1
fi

