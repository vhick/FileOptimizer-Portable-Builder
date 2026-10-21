param(
    [Parameter(Mandatory=$true)][string]$ExePath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
# Read ALL sizes from the application's official RT_GROUP_ICON and RT_ICON PE resources.
# Never substitute a generic icon. Fails the build when upstream icon cannot be read.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class OfficialIconExport {
  const uint LOAD_LIBRARY_AS_DATAFILE = 2;
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr LoadLibraryEx(string file, IntPtr hFile, uint flags);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool FreeLibrary(IntPtr hModule);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, EntryPoint="EnumResourceNamesW", SetLastError=true)]
  static extern bool EnumResourceNames(IntPtr hModule, IntPtr type, EnumNameCallback callback, IntPtr lParam);
  delegate bool EnumNameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr lParam);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, EntryPoint="FindResourceW", SetLastError=true)]
  static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern IntPtr LoadResource(IntPtr module, IntPtr res);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern IntPtr LockResource(IntPtr res);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern uint SizeofResource(IntPtr module, IntPtr res);
  static byte[] ReadResource(IntPtr module, IntPtr name, int type) {
    IntPtr refHandle=FindResource(module, name, new IntPtr(type));
    if(refHandle==IntPtr.Zero) throw new Exception("Missing icon resource type " + type);
    uint size=SizeofResource(module,refHandle);
    IntPtr loaded=LoadResource(module,refHandle), ptr=LockResource(loaded);
    if(ptr==IntPtr.Zero||size<1||size>20000000) throw new Exception("Invalid icon resource");
    byte[] data=new byte[(int)size]; Marshal.Copy(ptr,data,0,(int)size); return data;
  }
  public static void Export(string exe, string output) {
    IntPtr module=LoadLibraryEx(exe, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
    if(module==IntPtr.Zero) throw new Exception("Cannot load vendor EXE resources");
    try {
      IntPtr groupName=IntPtr.Zero;
      EnumNameCallback callback=delegate(IntPtr h, IntPtr typ, IntPtr name, IntPtr arg) {
        if(groupName==IntPtr.Zero) groupName=name;
        return true;
      };
      EnumResourceNames(module,new IntPtr(14),callback,IntPtr.Zero);
      GC.KeepAlive(callback);
      if(groupName==IntPtr.Zero) throw new Exception("Vendor EXE has no RT_GROUP_ICON");
      byte[] group=ReadResource(module,groupName,14);
      int count=BitConverter.ToUInt16(group,4);
      if(group.Length<6||BitConverter.ToUInt16(group,2)!=1||count<1||count>64||group.Length<6+count*14)
        throw new Exception("Invalid RT_GROUP_ICON data");
      List<byte[]> icons=new List<byte[]>();
      for(int i=0;i<count;i++) {
        int offset=6+i*14;
        ushort id=BitConverter.ToUInt16(group,offset+12);
        byte[] pngOrBmp=ReadResource(module,new IntPtr(id),3);
        icons.Add(pngOrBmp);
      }
      Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
      using(FileStream stream=File.Create(output)) using(BinaryWriter writer=new BinaryWriter(stream)) {
        writer.Write((ushort)0); writer.Write((ushort)1); writer.Write((ushort)count);
        uint dataOffset=(uint)(6+count*16);
        for(int i=0;i<count;i++) {
          int offset=6+i*14;
          writer.Write(group,offset,4);
          writer.Write(BitConverter.ToUInt16(group,offset+4));
          writer.Write(BitConverter.ToUInt16(group,offset+6));
          writer.Write((uint)icons[i].Length);
          writer.Write(dataOffset);
          dataOffset+=(uint)icons[i].Length;
        }
        foreach(byte[] icon in icons) writer.Write(icon);
      }
    } finally { FreeLibrary(module); }
  }
}
'@ -ErrorAction Stop
[OfficialIconExport]::Export((Resolve-Path $ExePath).Path, $OutputPath)
if ((Get-Item -LiteralPath $OutputPath).Length -lt 100) { throw 'Official ICO unexpectedly small' }
Write-Host "Extracted original multi-resolution FluentCleaner icon: $OutputPath"
