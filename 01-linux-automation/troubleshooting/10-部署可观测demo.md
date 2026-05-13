```shell
helm repo update
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

helm search repo open-telemetry/opentelemetry-demo --versions || head -10
helm pull open-telemetry/opentelemetry-demo --version 0.40.0 --untar
helm pull open-telemetry/opentelemetry-demo --version 0.40.0

cd opentelemetry-demo/

helm template my-otel-demo . --include-crds | \
  grep "image:" | \
  awk '{print $2}' | \
  sed "s/['\"]//g" | \
  sort -u > final-image-list.txt

# 1. 拉取完整的 opentelemetry-demo 目录（包含 charts 依赖）
scp -r us:~/opentelemetry-demo .

# 2. 拉取镜像列表文件
scp us:~/final-image-list.txt .

# 3. 拉取 components.yaml（如果有用也带上）
scp us:~/components.yaml .
# 4.拉取原始压缩包
scp us:~/opentelemetry-demo-0.40.0.tgz .

tmux new -s sync-otel
cd ~/scripts
./sync_to_harbor_simple.sh -f ~/final-image-list.txt 5000


# 这一行命令下去，任务就在后台跑了，你甚至不需要进入 tmux 界面
tmux new -s sync-otel -d 'cd ~/scripts && ./sync_to_harbor_simple.sh -f ~/final-image-list.txt 5000'
# 挂在后台
按住 Ctrl 键不放。
按一下 b 键（此时 Ctrl 和 b 同时被按下）。
松开 这两个键。
单独按一下 d 键。
# 回到前台
tmux ls
tmux attach -t sync-otel
tmux capture-pane -p -t sync-otel
```