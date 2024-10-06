#!/bin/bash
function build(){
    remote_directory_path="/www/wwwroot/tinypng.wcrane.cn"
    password="Xsx.315211"
    ip=root@39.107.82.50
    export NODE_OPTIONS=--max_old_space_size=8096
    git add .
    git commit -m "feat: update docs"
    git push 
    # 执行打包命令
    yarn build || exit 1
    # 压缩打包后的文件
    cd ./doc_build && zip -r ./build.zip ./*
    sshpass -p$password ssh $ip rm -rf $remote_directory_path/* || exit 1
    sshpass -p$password scp ./build.zip $ip:$remote_directory_path || exit 1
    # 迁移压缩文件到服务器对应目录下
    sshpass -p$password ssh $ip "cd $remote_directory_path  && unzip ./build.zip -d ./ && rm -rf ./build.zip" || exit 1
    rm -rf build.zip
}

function buildExapmle(){
    remote_directory_path="/www/wwwroot/tinypng.wcrane.cn"
    demo_path="/www/wwwroot/tinypng.wcrane.cn/example"
    password="Xsx.315211"
    ip=root@39.107.82.50
    export NODE_OPTIONS=--max_old_space_size=8096
    pwd || exit 1
    cd ../../tinypng-lib/www && pwd|| exit 1
    # 执行打包命令
    yarn build || exit 1
    # 压缩打包后的文件
    cd ./dist && zip -r ./build.zip ./* || exit 1
    sshpass -p$password ssh $ip rm -rf $demo_path/* || exit 1
    sshpass -p$password scp ./build.zip $ip:$remote_directory_path || exit 1
    # # 迁移压缩文件到服务器对应目录下
    sshpass -p$password ssh $ip "cd $remote_directory_path  && unzip ./build.zip -d ./example && rm -rf ./build.zip" || exit 1
    rm -rf build.zip || exit 1
    # curl https://www.feishu.cn/flow/api/trigger-webhook/58e61316038b59bb6834ab42ab843b72
}

build 
buildExapmle


