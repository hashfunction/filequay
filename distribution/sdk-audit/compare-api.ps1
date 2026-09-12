param([Parameter(Mandatory=$true)][string]$BeforeArchive, [Parameter(Mandatory=$true)][string]$AfterArchive)
$ErrorActionPreference='Stop'
Add-Type @'
using System;using System.IO;using System.IO.Compression;using System.Reflection;using System.Reflection.Metadata;using System.Reflection.PortableExecutable;using System.Collections.Generic;using System.Collections.Immutable;
public sealed class SdkSignature:ISignatureTypeProvider<string,object> {
 public string GetArrayType(string e,ArrayShape s){return e+"[rank="+s.Rank+"]";}public string GetByReferenceType(string e){return e+"&";}
 public string GetFunctionPointerType(MethodSignature<string> s){return "fn:"+s.ReturnType+"("+String.Join(",",s.ParameterTypes)+")";}
 public string GetGenericInstantiation(string g,ImmutableArray<string> a){return g+"<"+String.Join(",",a)+">";}
 public string GetGenericMethodParameter(object c,int i){return "!!"+i;}public string GetGenericTypeParameter(object c,int i){return "!"+i;}
 public string GetModifiedType(string m,string e,bool required){return e+" mod"+(required?"req":"opt")+"("+m+")";}
 public string GetPinnedType(string e){return e+" pinned";}public string GetPointerType(string e){return e+"*";}
 public string GetPrimitiveType(PrimitiveTypeCode t){return t.ToString();}public string GetSZArrayType(string e){return e+"[]";}
 public string GetTypeFromDefinition(MetadataReader r,TypeDefinitionHandle h,byte k){var t=r.GetTypeDefinition(h);var p=t.GetDeclaringType();return (p.IsNil?r.GetString(t.Namespace):GetTypeFromDefinition(r,p,k))+"."+r.GetString(t.Name);}
 public string GetTypeFromReference(MetadataReader r,TypeReferenceHandle h,byte k){var t=r.GetTypeReference(h);return r.GetString(t.Namespace)+"."+r.GetString(t.Name);}
 public string GetTypeFromSpecification(MetadataReader r,object c,TypeSpecificationHandle h,byte k){return r.GetTypeSpecification(h).DecodeSignature(this,c);}
}
public static class SdkApi {
 public static SortedSet<string> Read(string path){var set=new SortedSet<string>(StringComparer.Ordinal);var p=new SdkSignature();
  using(var zip=ZipFile.OpenRead(path))using(var input=zip.GetEntry("lib/net8.0/Microsoft.Windows.SDK.NET.dll").Open())using(var b=new MemoryStream()){
   input.CopyTo(b);b.Position=0;using(var pe=new PEReader(b)){var r=pe.GetMetadataReader();
    foreach(var h in r.TypeDefinitions){var t=r.GetTypeDefinition(h);var a=t.Attributes&TypeAttributes.VisibilityMask;if(a!=TypeAttributes.Public && a!=TypeAttributes.NestedPublic && a!=TypeAttributes.NestedFamily && a!=TypeAttributes.NestedFamORAssem)continue;
     string n=p.GetTypeFromDefinition(r,h,0);set.Add("T "+n);
     foreach(var mh in t.GetMethods()){var m=r.GetMethodDefinition(mh);var access=m.Attributes&MethodAttributes.MemberAccessMask;if(access!=MethodAttributes.Public && access!=MethodAttributes.Family && access!=MethodAttributes.FamORAssem)continue;
      var sig=m.DecodeSignature(p,null);set.Add("M "+n+"."+r.GetString(m.Name)+"`"+sig.GenericParameterCount+" "+sig.ReturnType+"("+String.Join(",",sig.ParameterTypes)+") "+(m.Attributes&(MethodAttributes.Static|MethodAttributes.Virtual|MethodAttributes.Abstract)));
     }
     foreach(var fh in t.GetFields()){var f=r.GetFieldDefinition(fh);var access=f.Attributes&FieldAttributes.FieldAccessMask;if(access==FieldAttributes.Public || access==FieldAttributes.Family || access==FieldAttributes.FamORAssem)set.Add("F "+n+"."+r.GetString(f.Name)+" "+f.DecodeSignature(p,null));}
    }
   }
  }return set;
 }
}
'@
if ((Get-FileHash $BeforeArchive -Algorithm SHA256).Hash -ne '2a6f7f97e34e7cf0bbf5160edcf57d08d55018d9ecdd31b97a193ea64279862f') { throw 'Original preview archive hash differs.' }
if ((Get-FileHash $AfterArchive -Algorithm SHA256).Hash -ne 'e15559b82ccbcda51c897be9da3aa190887dba3ecb0d1bd9525130aaa9132f0d') { throw 'Original stable archive hash differs.' }
$before=[SdkApi]::Read($BeforeArchive)
$after=[SdkApi]::Read($AfterArchive)
$removed=@($before|Where-Object {-not $after.Contains($_)});$added=@($after|Where-Object {-not $before.Contains($_)})
@{before_public_signatures=$before.Count;after_public_signatures=$after.Count;removed=$removed;added_count=$added.Count;added_sample=@($added|Select-Object -First 12)}|ConvertTo-Json -Depth 5

if ($removed.Count) { throw 'The observed public API surface removed signatures.' }
