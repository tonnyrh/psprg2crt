<#
.SYNOPSIS
Converts a C64 PRG file to a CRT file compatible with various cartridge types, defaulting to EasyFlash.

.DESCRIPTION
This script reads a C64 PRG file and converts it to a CRT file format compatible with different cartridge types. 
The default cartridge type is EasyFlash, but other types such as Normal 8k, Normal 16k, Ultimax, and Ocean Type 1 are supported.
Based on Python script from Frank Buss https://frank-buss.de/c64/prg2crt/index.html

.PARAMETER inputPrg
Specifies the path to the input PRG file.

.PARAMETER outputCrt
Specifies the path to the output CRT file.

.PARAMETER cartridgeType
Specifies the cartridge type for the output CRT file. 
Valid values are "Normal8k", "Normal16k", "Ultimax", "OceanType1", "EasyFlash", and "EasyFlashXbank". 
The default value is "EasyFlash".

.EXAMPLE
.\prg2crt.ps1 -inputPrg "C:\path\to\input.prg" -outputCrt "C:\path\to\output.crt" -cartridgeType "EasyFlash"
#>

param (
    [string]$inputPrg,
    [string]$outputCrt,
    [ValidateSet("Normal8k", "Normal16k", "Ultimax", "OceanType1", "EasyFlash", "EasyFlashXbank")]
    [string]$cartridgeType = "EasyFlash"
)

# Function to convert hex string to byte array
function ConvertFrom-Hex {
    param (
        [string]$hexString
    )
    # Remove all non-hex characters
    $hexString = $hexString -replace '[^0-9A-Fa-f]', ''
    $bytes = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $hexString.Length; $i += 2) {
        [void]$bytes.Add([Convert]::ToByte($hexString.Substring($i, 2), 16))
    }
    return ,$bytes
}

# Helper function to write binary data to the CRT file
function Write-Hex {
    param (
        [string]$string
    )
    $bytes = ConvertFrom-Hex $string
    foreach ($byte in $bytes) {
        [void]$crtData.Add($byte)
    }
}

# Map cartridge types to hardware type codes
$cartridgeTypeMap = @{
    "Normal8k" = "00 00"
    "Normal16k" = "00 01"
    "Ultimax" = "00 02"
    "OceanType1" = "00 12"
    "EasyFlash" = "00 20"
    "EasyFlashXbank" = "00 21"
}

# Determine the hardware type based on the selected cartridge type
$hardwareTypeHex = $cartridgeTypeMap[$cartridgeType]

# Open PRG file and read into array
$prg = [System.IO.File]::ReadAllBytes($inputPrg)

# Output data array
$crtData = New-Object System.Collections.ArrayList

# CRT signature
Write-Hex '43 36 34 20 43 41 52 54 52 49 44 47 45 20 20 20'

# Header length
Write-Hex '00 00 00 40'

# Cartridge version
Write-Hex '01 00'

# Cartridge hardware type
Write-Hex $hardwareTypeHex

# EXROM status
Write-Hex '00'

# GAME status
Write-Hex '00'

# Reserved
Write-Hex '00 00 00 00 00 00'

# Cartridge name
Write-Hex ('00' * 32 -join ' ')

# ROM content
$content = New-Object System.Collections.ArrayList

# Add loader inline
$loaderHex = @'
09 80 09 80 C3 C2 CD 38 30 78 8E 16 D0 20 A3 FD 20 50 FD A9 A0 8D 84 02 20 15
FD 20 5B FF 58 20 53 E4 20 BF E3 20 22 E4 A2 FB 9A A9 00 85 57 AD 9A 80 85 58
AD 9B 80 85 59 AD 9C 80 85 2D AD 9D 80 85 2E A9 9E 85 5A A9 80 85 5B A2 00 BD
59 80 9D 00 06 E8 D0 F7 4C 00 06 78 A2 00 A5 57 8D 00 DE A1 5A 81 2D E6 5A D0
13 E6 5B A5 5B C9 A0 D0 0B A9 80 85 5B E6 57 A5 57 8D 00 DE E6 2D D0 02 E6 2E
C6 58 D0 DB C6 59 A5 59 C9 FF D0 D3 A9 80 8D 00 DE 20 63 A6 58 4C AE A7
'@

$loaderBytes = ConvertFrom-Hex $loaderHex
[void]$content.AddRange($loaderBytes)

# Add program size, minus the first two bytes for start address
$size = $prg.Length - 2
$content.Add($size -band 0xff)
$content.Add([math]::Floor($size / 0x100))

# Add program, with start address
[void]$content.AddRange($prg)

# Align to 0x2000 bytes
while ($content.Count % 0x2000 -ne 0) {
    $content.Add(0)
}

# Save content as Chip blocks
$banks = [math]::Floor($content.Count / 0x2000)
for ($bank = 0; $bank -lt $banks; $bank++) {
    # CHIP
    Write-Hex '43484950'
    
    # Total packet length: 0x2010 (ROM image size + CHIP header)
    Write-Hex '00 00 20 10'
    
    # Chip type: ROM
    Write-Hex '00 00'
    
    # Bank number
    $crtData.Add(0)
    $crtData.Add($bank)
    
    # Starting load address
    Write-Hex '80 00'
    
    # ROM image size
    Write-Hex '20 00'
    
    # 0x2000 bytes ROM image
    $start = 0x2000 * $bank
    $end = $start + 0x2000
    [void]$crtData.AddRange($content[$start..($end-1)])
}

# Save module
[System.IO.File]::WriteAllBytes($outputCrt, $crtData.ToArray())
