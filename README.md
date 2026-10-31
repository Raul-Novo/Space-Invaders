# Space Invaders

### 1. OVMF (solo una vez)

```powershell
New-Item -ItemType Directory -Force .\OVMF | Out-Null

$url = "https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF"

Invoke-WebRequest "$url/OVMF_CODE_4M.fd" -OutFile .\OVMF\OVMF_CODE_4M.fd
Invoke-WebRequest "$url/OVMF_VARS_4M.fd" -OutFile .\OVMF\OVMF_VARS_4M.fd

Copy-Item .\OVMF\OVMF_VARS_4M.fd .\OVMF\OVMF_VARS.fd
```

### 2. Compilar

```powershell
nasm -f win64 .\space_invaders_uefi.asm -o game.obj
if ($LASTEXITCODE -ne 0) { throw "NASM failed" }

lld-link /subsystem:efi_application /entry:efi_main /machine:x64 /nodefaultlib /out:BOOTX64.EFI game.obj
if ($LASTEXITCODE -ne 0) { throw "Link failed" }

New-Item -ItemType Directory -Force .\esp\EFI\BOOT | Out-Null
Copy-Item .\BOOTX64.EFI .\esp\EFI\BOOT\BOOTX64.EFI -Force
```

### 3. Ejecutar en QEMU

```powershell
$code = (Resolve-Path .\OVMF\OVMF_CODE_4M.fd).Path
$vars = (Resolve-Path .\OVMF\OVMF_VARS.fd).Path
$esp = (Resolve-Path .\esp).Path

qemu-system-x86_64 `
    -machine q35 `
    -m 512M `
    -vga std `
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" `
    -drive "if=pflash,format=raw,unit=1,file=$vars" `
    -drive "if=ide,format=raw,file=fat:rw:$esp" `
    -net none
```
