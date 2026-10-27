param(
    [Parameter(Mandatory=$true)][string]$ExePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$FallbackExePath = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Read the original vendor's RT_GROUP_ICON/RT_ICON resources. This preserves all
# embedded resolutions instead of taking a potentially generic shell file icon.
# Crucially, resource names returned by EnumResourceNamesW may be either numeric
# IDs OR temporary pointers to Unicode strings. Copy named resources into managed
# strings INSIDE the callback; never retain and later dereference the raw pointer.
if (-not ('OfficialIconExport' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class OfficialIconExport {
  const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;
  const uint LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x00000020;

  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, EntryPoint="LoadLibraryExW", SetLastError=true)]
  static extern IntPtr LoadLibraryEx(string file, IntPtr hFile, uint flags);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool FreeLibrary(IntPtr module);
  [UnmanagedFunctionPointer(CallingConvention.Winapi)]
  delegate bool EnumNameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr lParam);
  [DllImport("kernel32.dll", EntryPoint="EnumResourceNamesW", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool EnumResourceNames(IntPtr module, IntPtr type, EnumNameCallback callback, IntPtr lParam);
  [DllImport("kernel32.dll", EntryPoint="FindResourceW", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr FindResourceById(IntPtr module, IntPtr name, IntPtr type);
  [DllImport("kernel32.dll", EntryPoint="FindResourceW", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr FindResourceByName(IntPtr module, string name, IntPtr type);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern IntPtr LockResource(IntPtr resource);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern uint SizeofResource(IntPtr module, IntPtr resource);

  sealed class ResourceName {
    internal readonly int Id;
    internal readonly string Name;
    internal bool IsNumeric { get { return Name == null; } }
    internal ResourceName(int id) { Id=id; Name=null; }
    internal ResourceName(string name) { Id=0; Name=name; }
    public override string ToString() { return IsNumeric ? ("#"+Id) : Name; }
    internal static ResourceName CopyFromCallback(IntPtr ptr) {
      // Win32 IS_INTRESOURCE: top bits empty means lower 16 bits are the ID.
      long v=ptr.ToInt64();
      if ((v & ~0xFFFFL) == 0) return new ResourceName((int)(v & 0xFFFF));
      string s=Marshal.PtrToStringUni(ptr);
      if (String.IsNullOrEmpty(s)) throw new Exception("Empty named icon resource");
      return new ResourceName(s);
    }
  }

  static byte[] ReadResource(IntPtr module, ResourceName name, int type) {
    IntPtr handle=name.IsNumeric
      ? FindResourceById(module, new IntPtr(name.Id), new IntPtr(type))
      : FindResourceByName(module, name.Name, new IntPtr(type));
    if (handle==IntPtr.Zero) throw new Exception("Missing resource type " + type + " name=" + name + ", Win32=" + Marshal.GetLastWin32Error());
    uint size=SizeofResource(module, handle);
    if (size < 1 || size > 20000000) throw new Exception("Invalid resource length " + size + " for " + name);
    IntPtr loaded=LoadResource(module, handle);
    if (loaded==IntPtr.Zero) throw new Exception("LoadResource failed for " + name);
    IntPtr ptr=LockResource(loaded);
    if (ptr==IntPtr.Zero) throw new Exception("LockResource failed for " + name);
    byte[] data=new byte[(int)size];
    Marshal.Copy(ptr, data, 0, data.Length);
    return data;
  }

  static void WriteIco(IntPtr module, ResourceName groupName, string output) {
    byte[] group=ReadResource(module, groupName, 14); // RT_GROUP_ICON
    if (group.Length<6) throw new Exception("Truncated RT_GROUP_ICON");
    int count=BitConverter.ToUInt16(group, 4);
    if (BitConverter.ToUInt16(group,0)!=0 || BitConverter.ToUInt16(group,2)!=1 || count<1 || count>64 || group.Length<6+count*14)
      throw new Exception("Invalid RT_GROUP_ICON directory from " + groupName);
    List<byte[]> payloads=new List<byte[]>();
    for(int i=0;i<count;i++) {
      int offset=6+i*14;
      int id=BitConverter.ToUInt16(group, offset+12);
      byte[] payload=ReadResource(module, new ResourceName(id), 3); // RT_ICON
      payloads.Add(payload);
    }
    Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
    // Build a full Windows .ico file with an ICO directory followed by the
    // exact original compressed PNG / DIB icon image resources.
    using(FileStream stream=File.Create(output))
    using(BinaryWriter writer=new BinaryWriter(stream)) {
      writer.Write((ushort)0); writer.Write((ushort)1); writer.Write((ushort)count);
      uint dataOffset=(uint)(6+count*16);
      for(int i=0;i<count;i++) {
        int offset=6+i*14;
        writer.Write(group, offset, 4); // width, height, colors, reserved
        writer.Write(BitConverter.ToUInt16(group, offset+4)); // planes
        writer.Write(BitConverter.ToUInt16(group, offset+6)); // bit depth
        writer.Write((uint)payloads[i].Length);
        writer.Write(dataOffset);
        dataOffset+=(uint)payloads[i].Length;
      }
      foreach(byte[] payload in payloads) writer.Write(payload);
    }
  }

  public static string Export(string exe, string output) {
    IntPtr module=LoadLibraryEx(exe, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
    if(module==IntPtr.Zero) throw new Exception("Cannot load vendor EXE resources (Win32=" + Marshal.GetLastWin32Error() + "): " + exe);
    try {
      List<ResourceName> groups=new List<ResourceName>();
      List<string> enumerationErrors=new List<string>();
      EnumNameCallback callback=delegate(IntPtr h, IntPtr typ, IntPtr ptr, IntPtr arg) {
        try { groups.Add(ResourceName.CopyFromCallback(ptr)); }
        catch (Exception e) { enumerationErrors.Add(e.Message); }
        return true;
      };
      EnumResourceNames(module, new IntPtr(14), callback, IntPtr.Zero);
      GC.KeepAlive(callback);
      if(groups.Count==0) throw new Exception("No RT_GROUP_ICON resources in vendor EXE (Win32=" + Marshal.GetLastWin32Error() + "). " + String.Join("; ", enumerationErrors.ToArray()));
      List<string> errors=new List<string>();
      foreach(ResourceName group in groups) {
        try {
          WriteIco(module, group, output);
          return group.ToString();
        } catch(Exception e) { errors.Add(group + ": " + e.Message); }
      }
      throw new Exception("All " + groups.Count + " official icon groups failed: " + String.Join("; ", errors.ToArray()));
    } finally { FreeLibrary(module); }
  }
}
'@ -ErrorAction Stop
}

$candidates = @($ExePath)
if ($FallbackExePath -and (Test-Path -LiteralPath $FallbackExePath -PathType Leaf)) {
    $candidates += $FallbackExePath
}
$errors = @()
foreach ($candidate in $candidates) {
    try {
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $groupName = [OfficialIconExport]::Export($resolved, $OutputPath)
        $bytes = [System.IO.File]::ReadAllBytes($OutputPath)
        if ($bytes.Length -lt 100 -or $bytes[0] -ne 0 -or $bytes[1] -ne 0 -or $bytes[2] -ne 1 -or $bytes[3] -ne 0 -or [BitConverter]::ToUInt16($bytes,4) -lt 1) {
            throw 'Extracted ICO is unexpectedly small or has an invalid ICO header.'
        }
        Write-Host "PASS: Extracted original vendor icon from $([IO.Path]::GetFileName($resolved)) (group $groupName; $($bytes.Length) bytes)"
        return
    } catch {
        $errors += "$candidate : $($_.Exception.Message)"
        if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
        Write-Warning "Official vendor icon extraction failed for $candidate : $($_.Exception.Message)"
    }
}
throw ("Could not extract the authentic FileOptimizer icon. No generic icon was substituted. " + ($errors -join ' | '))
