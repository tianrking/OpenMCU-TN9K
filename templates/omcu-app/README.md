# OpenMCU-TN9K 独立应用模板

这个目录可以复制到 OpenMCU 仓库之外，应用源码不会修改 FPGA RTL 或 SDK。它通过
`sdk/cmake/OpenMCUSDK.cmake` 引用固定 SDK，并生成可由产品 Bootloader 独立烧录的
`build/my_omcu_app.omcu`。

## macOS / Linux

```sh
cp -R /path/to/OpenMCU-TN9K/templates/omcu-app ~/my-omcu-app
cd ~/my-omcu-app
export OMCU_SDK_PATH=/path/to/OpenMCU-TN9K/sdk
export PATH=/path/to/riscv-none-elf/bin:$PATH

./build.sh
./flash.sh /dev/cu.usbserial-XXXX
```

Linux 串口通常是 `/dev/ttyUSB0` 或 `/dev/ttyACM0`。

## Windows PowerShell

```powershell
Copy-Item -Recurse C:\src\OpenMCU-TN9K\templates\omcu-app C:\src\my-omcu-app
Set-Location C:\src\my-omcu-app
$env:OMCU_SDK_PATH = 'C:\src\OpenMCU-TN9K\sdk'
$env:PATH = "C:\toolchains\riscv-none-elf\bin;$env:PATH"

.\build.ps1
.\flash.ps1 -Port COM5
```

主机需有 CMake 3.20+、Ninja、Python 3 和 `riscv-none-elf-gcc/objcopy`；烧录还需
`python -m pip install pyserial`。烧录工具开始握手后，若当前应用正在运行，按一次板上复位键。

## 开发约定

- 在 `src/` 增加自己的 C 文件，并列入 `CMakeLists.txt` 的 `omcu_add_application()`。
- 需要外置器件驱动时链接 `OpenMCU::device_drivers`。
- 只发布 `.omcu` 给应用升级流程；保留 `.elf` 与 `.map` 用于调试和空间审计。
- UART0 是 Bootloader 与默认日志口，应用和下载器不能同时占用它。
- 每次构建都会校验 ABI、最大载荷和 CRC；不要手工制作镜像头。
