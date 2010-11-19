unit ScaleMM;

interface

const
  C_ARRAYSIZE          = 50;  //alloc memory blocks with 50 memory items each time
  C_GLOBAL_BLOCK_CACHE = 10;  //keep 10 free blocks in cache

{$DEFINE SCALE_INJECT_OFFSET}  //2% faster

//other posible defines:
//{$DEFINE PURE_PASCAL}        //no assembly, pure delphi code
//{$DEFINE Align16Bytes}       //16 byte aligned header, so some more overhead
//{$DEFINE DEBUG_SCALEMM}      //slower but better debugging (no inline functions etc)

{$IFDEF DEBUG_SCALEMM}
  {$Optimization   OFF}
  {$STACKFRAMES    ON}
  {$ASSERTIONS     ON}
  {$DEBUGINFO      ON}
  {$OVERFLOWCHECKS ON}
  {$RANGECHECKS    ON}
{$ELSE}      //default "release" mode, much faster!
  {$Optimization   ON}         //235% faster!
  {$STACKFRAMES    OFF}        //12% faster
  {$ASSERTIONS     OFF}
  //{$DEBUGINFO      OFF}      //not faster so keep it on?
  {$OVERFLOWCHECKS OFF}
  {$RANGECHECKS    OFF}
{$ENDIF}

//todo: prefetch memory after alloc ivm class create, strings etc?

type
  PMemBlock         = ^TMemBlock;
  PMemBlockList     = ^TMemBlockList;
  PThreadMemManager = ^TThreadMemManager;
  PMemHeader        = ^TMemHeader;

  TMemHeader = record
    Owner    : PMemBlock;
    NextMem  : PMemHeader;  //linked to next single memory item (other thread freem mem)
                            //also 8byte aligned
    {$IFDEF Align16Bytes}
    Filer1: Pointer;
    Filer2: Pointer;        //16byte aligned
    {$ENDIF}
  end;

  TMemBlock = record
    Owner: PMemBlockList;

    { TODO -oAM : todo: one double linked list? }
    //linked to next list with freed memory, in case this list has no more freed mem
    FNextFreedMemBlock: PMemBlock;
    //linked to next list with free memory
    FNextMemBlock     : PMemBlock;
    //double linked, to be able for fast removal of one block
    FPreviousMemBlock     : PMemBlock;
    FPreviousFreedMemBlock: PMemBlock;

    FMemoryArray: Pointer;    //array[CARRAYSIZE] of memory items
    FUsageCount : Byte;       //how much free mem is used, max is CARRAYSIZE

    FFreedIndex: Byte;
    FFreedArray: array[0..C_ARRAYSIZE] of Pointer;

    function  GetUsedMemoryItem: PMemHeader;    {$ifNdef DEBUG_SCALEMM}inline;{$ENDIF}
    procedure FreeMem(aMemoryItem: PMemHeader); {$ifNdef DEBUG_SCALEMM}inline;{$ENDIF}

    procedure AllocBlockMemory;
    procedure FreeBlockMemoryToGlobal;
  end;

  { TODO : special record for medium/large blocks }
  //TMediumMemoryList = record

  TMemBlockList = record
    //list with freed memory (which this block owns)
    FFirstFreedMemBlock: PMemBlock;
    //list with all memory this block owns
    FFirstMemBlock     : PMemBlock;
    { TODO -oAM : also last block to append free block etc instead of front? }

    //size of memory items (32, 64 etc bytes)
    FItemSize : Word;   //0..65535
    Owner     : PThreadMemManager;

    //recursive check when we alloc memory for this blocksize (new memory list)
    FRecursive: boolean;

    FFreeMemCount: NativeInt;

    procedure AddNewMemoryBlock;
    function  GetMemFromNewBlock : Pointer;
    function  GetMemFromUsedBlock: Pointer; {$ifNdef DEBUG_SCALEMM}inline;{$ENDIF}
  end;

  TThreadMemManager = record
  private
    //linked list of mem freed in other thread
    FOtherThreadFreedMemory: PMemHeader;
    procedure ProcessFreedMemFromOtherThreads;
    procedure AddFreedMemFromOtherThread(aMemory: PMemHeader);

    //array with memory per block size (32 - 256 bytes)
    var FMiniMemoryBlocks  : array[0..7] of TMemBlockList;
    //array with memory per block size (256 - 2048 bytes)
    var FSmallMemoryBlocks : array[0..7] of TMemBlockList;
    //array with (dynamic) memory per block size 256 (2048 - 16384/18432 bytes)
    var FMediumMemoryBlocks: array[0..63] of PMemBlockList;

    //linked list of items to reuse after thread terminated
    FNextThreadManager: PThreadMemManager;

    function  GetLargerMem(aSize: NativeInt): Pointer;
    function  GetOldMem   (aSize: NativeInt): Pointer;
    function  FreeOldMem  (aMemory: Pointer): NativeInt;
  public
    FThreadId: NativeUInt;
    FThreadTerminated: Boolean;  //is this thread memory available to new thread?

    procedure Init;
    procedure Reset;

    function GetMem (aSize: NativeInt): Pointer;   {$ifNdef DEBUG_SCALEMM}inline;{$ENDIF}
    function FreeMem(aMemory: Pointer): NativeInt; {$ifNdef DEBUG_SCALEMM}inline;{$ENDIF}
  end;

  /// <summary>
  /// Global memory manager (single instance), caches some memory (blocks + threadmem) for fast reuse.
  /// Also keeps allocated memory in case an old thread allocated some memory for another thread
  /// </summary>
  TGlobalMemManager = record
  private
    //all thread memory managers
    FFirstThreadMemory: PThreadMemManager;
    //freed/used thread memory managers
    FFirstFreedThreadMemory: PThreadMemManager;
    //main thread manager (owner of all global mem)
    FMainThreadMemory: PThreadMemManager;

    //Freed/used memory:
    //array with memory per block size (32 - 256 bytes)
    var FFreedMiniMemoryBlocks  : array[0..7] of TMemBlockList;
    //array with memory per block size (256 - 2048 bytes)
    var FFreedSmallMemoryBlocks : array[0..7] of TMemBlockList;
    //array with (dynamic) memory per block size 256 (2048 - 16384/18432 bytes)
    var FFreedMediumMemoryBlocks: array[0..63] of TMemBlockList;

    procedure Init;
    procedure FreeAllMemory;
    procedure FreeBlocksFromThreadMemory(aThreadMem: PThreadMemManager);
  public
    class constructor Create;
    class destructor  Destroy;

    procedure AddNewThreadManagerToList(aThreadMem: PThreadMemManager);
    //
    procedure FreeThreadManager(aThreadMem: PThreadMemManager);
    function  GetNewThreadManager: PThreadMemManager;

    procedure FreeBlockMemory(aBlockMem: PMemBlock);
    function  GetBlockMemory (aItemSize: NativeInt): PMemBlock;
  end;

  function GetCurrentThreadManager: PThreadMemManager;

  function Scale_GetMem(aSize: Integer)   : Pointer;    //cannot use NativeInt?
  function Scale_AllocMem(aSize: Cardinal): Pointer;    //cannot use NativeUInt?
  function Scale_FreeMem(aMemory: Pointer): Integer;
  function Scale_ReallocMem(aMemory: Pointer; aSize: Integer): Pointer;

var
  GlobalManager: TGlobalMemManager;

implementation

//uses
//  Windows, SysUtils, Classes, Contnrs;  do not use other units!

///////////////////////////////////////////////////////////////////////////////

{$REGION 'Windows API functions'}
//Windows.pas unit cannot be used
type
  DWORD = LongWord;
  BOOL  = LongBool;
const
  PAGE_EXECUTE_READWRITE = $40;
  kernel32  = 'kernel32.dll';

function  TlsAlloc: DWORD; stdcall; external kernel32 name 'TlsAlloc';
function  TlsGetValue(dwTlsIndex: DWORD): Pointer; stdcall; external kernel32 name 'TlsGetValue';
function  TlsSetValue(dwTlsIndex: DWORD; lpTlsValue: Pointer): BOOL; stdcall; external kernel32 name 'TlsSetValue';
function  TlsFree(dwTlsIndex: DWORD): BOOL; stdcall; external kernel32 name 'TlsFree';
procedure Sleep(dwMilliseconds: DWORD); stdcall; external kernel32 name 'Sleep';
function  FlushInstructionCache(hProcess: THandle; const lpBaseAddress: Pointer; dwSize: DWORD): BOOL; stdcall; external kernel32 name 'FlushInstructionCache';
function  GetCurrentProcess: THandle; stdcall; external kernel32 name 'GetCurrentProcess';
function  GetCurrentThreadId: DWORD; stdcall; external kernel32 name 'GetCurrentThreadId';
function  Scale_VirtualProtect(lpAddress: Pointer; dwSize, flNewProtect: DWORD;
            var OldProtect: DWORD): BOOL; stdcall; overload; external kernel32 name 'VirtualProtect';
procedure ExitThread(dwExitCode: DWORD); stdcall; external kernel32 name 'ExitThread';

procedure ZeroMemory(Destination: Pointer; Length: DWORD);inline;
begin
  FillChar(Destination^, Length, 0);
end;

function SetPermission(Code: Pointer; Size, Permission: Cardinal): Cardinal;
begin
  Assert(Assigned(Code) and (Size > 0));
  { Flush the instruction cache so changes to the code page are effective immediately }
  if Permission <> 0 then
    if FlushInstructionCache(GetCurrentProcess, Code, Size) then
      if not Scale_VirtualProtect(Code, Size, Permission, Longword(Result)) then
        sleep(0);
end;
{$ENDREGION 'Windows API functions'}

//ScaleMM works on top of previous MM!
//e.g. large blocks are delegated to OldMM, but also block memory is allocated
//by OldMM if ScaleMM needs more memory itself (tries to use own memory first)
var
  OldMM: TMemoryManagerEx;

{$IFDEF PURE_PASCAL}
threadvar
  GCurrentThreadManager: PThreadMemManager;
{$ELSE}
{$REGION 'TLS AssemblyHacking'}
var
  GOwnTlsIndex,
  GOwnTlsOffset: NativeUInt;

function _GetOwnTls: Pointer;        //7% faster if we use this low level assembly!
asm
{$IFDEF SCALE_INJECT_OFFSET}
  MOV   EAX, 123456789               //dummy value: calc once and inject runtime
{$ELSE}
  MOV   EAX, GOwnTlsOffset           //2% slower, so we default use injected offset
{$ENDIF}
  MOV   ECX, fs:[$00000018]
//  MOV   EAX, [ECX+ EAX*4+$0e10]
  MOV   EAX, [ECX + EAX]             //fixed offset, calc only once
end;

procedure _FixedOffset;
{$IFDEF SCALE_INJECT_OFFSET}
var p: pointer;
{$ENDIF}
begin
  GOwnTlsOffset := GOwnTlsIndex * 4 + $0e10;

  {$IFDEF SCALE_INJECT_OFFSET}
  p  := @_GetOwnTls;
  SetPermission(p, 5, PAGE_EXECUTE_READWRITE);
  inc(PByte(p));
  PCardinal(p)^ := GOwnTlsOffset;  //write fixed offset (so no calculation + slow global var value fetch)
  {$ENDIF}
end;
{$ENDREGION 'TLS AssemblyHacking'}
{$ENDIF}

//compare oldvalue with destination: if equal then newvalue is set
function CAS32(const oldValue: pointer; newValue: pointer; var destination): boolean;
asm
  lock cmpxchg dword ptr [destination], newValue
  setz  al
end; { CAS32 }

{Compare [AAddress], CompareVal:
 If Equal: [AAddress] := NewVal and result = CompareVal
 If Unequal: Result := [AAddress]}
function LockCmpxchg(CompareVal, NewVal: Byte; AAddress: PByte): Byte;
asm
  {On entry:
    al = CompareVal,
    dl = NewVal,
    ecx = AAddress}
  lock cmpxchg [ecx], dl
end;

{$ifNdef DEBUG_SCALEMM}
procedure DummyAssert(aBoolean: boolean);
begin
  //
end;
{$ELSE}
procedure Assert(aCondition: boolean);
begin
  if not aCondition then
  begin
    asm
      int 3;
    end;
    Sleep(0);  //no exception, just dummy for breakpoint
  end;
end;
{$ENDIF}

///////////////////////////////////////////////////////////////////////////////

function CreateSmallMemManager: PThreadMemManager;
//var
//  pprevthreadmem: PThreadMemManager;
begin
  Result := GlobalManager.GetNewThreadManager;
  if Result = nil then
  begin
    Result := OldMM.GetMem( SizeOf(TThreadMemManager) );
    InitializeArray(Result, TypeInfo(TThreadMemManager),1);
    Result.Init;
  end
  else
  begin
    Result.FThreadId := GetCurrentThreadId;
    Result.FThreadTerminated := False;
  end;

  {$IFDEF PURE_PASCAL}
  GCurrentThreadManager := Result;
  {$ELSE}
  TlsSetValue(GOwnTLSIndex, Result);
  {$ENDIF}

//  GlobalManager.AddNewThreadMemoryToList(Result);
end;

function GetSmallMemManager: PThreadMemManager;inline;
begin
  {$IFDEF PURE_PASCAL}
  Result := GCurrentThreadManager;
  {$ELSE}
  Result := _GetOwnTls;
  {$ENDIF}
  if Result <> nil then
    Exit   //fast branch prediction
  else
    Result := CreateSmallMemManager;
end;

function GetCurrentThreadManager: PThreadMemManager;
begin
  Result := GetSmallMemManager;
end;

///////////////////////////////////////////////////////////////////////////////
{ TThreadMemManager }

procedure TThreadMemManager.Init;
var i: Byte;
begin
  FThreadId := GetCurrentThreadId;

  //init mini
  for i := Low(FMiniMemoryBlocks) to High(FMiniMemoryBlocks) do
  begin
    FMiniMemoryBlocks[i].Owner               := @Self;
    FMiniMemoryBlocks[i].FFirstMemBlock      := nil;
    FMiniMemoryBlocks[i].FFirstFreedMemBlock := nil;
    FMiniMemoryBlocks[i].FItemSize           := (i+1) * 32;
  end;

  //init small
  for i := Low(FSmallMemoryBlocks) to High(FSmallMemoryBlocks) do
  begin
    FSmallMemoryBlocks[i].Owner               := @Self;
    FSmallMemoryBlocks[i].FFirstMemBlock      := nil;
    FSmallMemoryBlocks[i].FFirstFreedMemBlock := nil;
    FSmallMemoryBlocks[i].FItemSize           := (i+1) * 256;
  end;
end;

procedure TThreadMemManager.ProcessFreedMemFromOtherThreads;
var
  pcurrentmem, pnextmem: PMemHeader;
begin
  while FOtherThreadFreedMemory <> nil do
  begin
    repeat
      pcurrentmem := FOtherThreadFreedMemory;
      pnextmem    := pcurrentmem.NextMem;
      //set next item as first (to remove first item from linked list)
      if CAS32(pcurrentmem, pnextmem, FOtherThreadFreedMemory) then
        Break;
      Sleep(0);
    until True = False;

    //free mem
    pcurrentmem.Owner.FreeMem(pcurrentmem);
  end;
end;

procedure TThreadMemManager.Reset;
var
  i: Byte;

  procedure __ResetBlocklist(aBlocklist: PMemBlockList);
  begin
    aBlocklist.FFirstFreedMemBlock := nil;
    aBlocklist.FFirstMemBlock      := nil;
    //aBlocklist.Owner               := nil;
    aBlocklist.FRecursive          := False;
  end;

begin
  FThreadId               := 0;
  FThreadTerminated       := True;
  FOtherThreadFreedMemory := nil;
  FNextThreadManager      := nil;

  for i := Low(FMiniMemoryBlocks) to High(FMiniMemoryBlocks) do
    __ResetBlocklist(@FMiniMemoryBlocks[i]);
  for i := Low(FSmallMemoryBlocks) to High(FSmallMemoryBlocks) do
    __ResetBlocklist(@FSmallMemoryBlocks[i]);
//  for i := Low(FMediumMemoryBlocks) to High(FMediumMemoryBlocks) do
//    __ResetBlocklist(@FMediumMemoryBlocks[i]);
end;

procedure TThreadMemManager.AddFreedMemFromOtherThread(aMemory: PMemHeader);
var
  poldmem: PMemHeader;
begin
  repeat
    poldmem := FOtherThreadFreedMemory;
    //set new item as first (to created linked list)
    if CAS32(poldmem, aMemory, FOtherThreadFreedMemory) then
      Break;
    Sleep(0);
  until True = False;

  FOtherThreadFreedMemory.NextMem := poldmem;
end;

function TThreadMemManager.FreeMem(aMemory: Pointer): NativeInt;
var
  pm: PMemBlock;
  p: Pointer;
begin
  p  := Pointer(NativeUInt(aMemory) - SizeOf(TMemHeader));
  pm := PMemHeader(p).Owner;

  Result := 0; // No Error result for Delphi

  if FOtherThreadFreedMemory <> nil then
    ProcessFreedMemFromOtherThreads;

  //oldmm?
  if pm <> nil then
  with pm^ do
  begin
    Assert(Owner <> nil);
    Assert(Owner.Owner <> nil);

    if Owner.Owner = @Self then  //mem of own thread?    //slow?
      FreeMem(PMemHeader(p))
    else
    //mem of other thread
    begin
      //put mem in lockfree queue of owner thread
      Owner.Owner.AddFreedMemFromOtherThread(PMemHeader(p));
    end;
  end
  else
    Result := FreeOldMem(p);
end;

function TThreadMemManager.FreeOldMem(aMemory: Pointer): NativeInt;
begin
 Result := OldMM.FreeMem(aMemory);
end;

function TThreadMemManager.GetLargerMem(aSize: NativeInt): Pointer;
begin
  Result := GetOldMem(aSize);

  //FMediumMemoryBlocks (64x 256 + 2048 bytes)
  //if block not yet then add, else normal stuff
end;

function TThreadMemManager.GetMem(aSize: NativeInt): Pointer;
var
  i: Byte;
  bm: PMemBlockList;
begin
  //mini block?
  if aSize <= 8 * 32 then
  begin
    if aSize <= 0 then Exit(nil);

    //i  := (aSize-1) div 32;       //blocks of 32: 32, 64, 96, etc till 256
    i  := (aSize-1) shr 5;       //blocks of 32: 32, 64, 96, etc till 256
    bm := @FMiniMemoryBlocks[i]
  end
  //small block?
  else if aSize <= 8 * 256 then
  begin
//    i  := (aSize-1) div 256;    //blocks of 256: 256, 512, 768, etc till 2048
    i  := (aSize-1) shr 8;    //blocks of 256: 256, 512, 768, etc till 2048
    bm := @FSmallMemoryBlocks[i]
  end
  else
  //medium or larger blocks
  begin
    Result := GetLargerMem(aSize);
    Exit;
  end;

  if FOtherThreadFreedMemory <> nil then
    ProcessFreedMemFromOtherThreads;

  with bm^ do
  begin
    //first get from freed mem (fastest because most chance?)
    if FFirstFreedMemBlock <> nil then
      Result := GetMemFromUsedBlock
    else
      //from normal list
      Result := GetMemFromNewBlock;
  end;

  Assert(NativeUInt(Result) > $10000);
  Result  := Pointer(NativeUInt(Result) + SizeOf(TMemHeader));
end;

function TThreadMemManager.GetOldMem(aSize: NativeInt): Pointer;
begin
  Result := OldMM.GetMem(aSize + SizeOf(TMemHeader));
  TMemHeader(Result^).Owner := nil;  //not our memlist, so nil, so we can check on this
  Result := Pointer(NativeUInt(Result) + SizeOf(TMemHeader) );
end;

///////////////////////////////////////////////////////////////////////////////
{ TMemBlock }

procedure TMemBlock.AllocBlockMemory;
begin
//  FMemoryArray := OldMM.GetMem( (Owner.FItemSize + SizeOf(TMemHeader))
//                                * C_ARRAYSIZE );
  FMemoryArray := Scale_GetMem( (Owner.FItemSize + SizeOf(TMemHeader))
                                * C_ARRAYSIZE );
end;

procedure TMemBlock.FreeBlockMemoryToGlobal;
begin
  //remove ourselves from linked list
  if FPreviousMemBlock <> nil then
    FPreviousMemBlock.FNextMemBlock := Self.FNextMemBlock;
  if FPreviousFreedMemBlock <> nil then
    FPreviousFreedMemBlock.FNextFreedMemBlock := Self.FNextFreedMemBlock;
  if FNextMemBlock <> nil then
    FNextMemBlock.FPreviousMemBlock := Self.FPreviousMemBlock;
  if FNextFreedMemBlock <> nil then
    FNextFreedMemBlock.FPreviousFreedMemBlock := Self.FPreviousFreedMemBlock;

  if Owner.FFirstFreedMemBlock = @Self then
    Owner.FFirstFreedMemBlock := nil;
  if Owner.FFirstMemBlock = @Self then
    Owner.FFirstMemBlock := nil;

  GlobalManager.FreeBlockMemory(@Self);
end;

procedure TMemBlock.FreeMem(aMemoryItem: PMemHeader);
begin
  //first free item of block?
  //then we add this block to (linked) list with available mem
  if FFreedIndex = 0 then
    with Owner^ do  //faster
    begin
      {Self.}FNextFreedMemBlock     := {Owner}FFirstFreedMemBlock;   //link to first list
      {Self.}FPreviousFreedMemBlock := nil;
      if {Self}FNextFreedMemBlock <> nil then
        {Self}FNextFreedMemBlock.FPreviousFreedMemBlock := @Self; //back link
      {Owner}FFirstFreedMemBlock    := @Self;                     //replace first list
    end;

  //free mem block
  FFreedArray[FFreedIndex] := aMemoryItem;
  inc(FFreedIndex);

  //all memory available?
  if FFreedIndex = C_ARRAYSIZE then
  //if FFreedIndex = FUsageCount then     we do not use this one, we want to keep at least one block (?)
  begin
    with Owner^ do
    begin
      Self.FreeBlockMemoryToGlobal;
    end;
  end;
end;

function TMemBlock.GetUsedMemoryItem: PMemHeader;
begin
  Assert(Self.Owner <> nil);
  Assert(FFreedIndex > 0);

  dec(FFreedIndex);
  Result := FFreedArray[FFreedIndex];

  if FFreedIndex = 0 then  //no free items left?
  begin
    //set next free memlist
    Owner.FFirstFreedMemBlock := {Self.}FNextFreedMemBlock;
    //first one has no previous
    if {Self.}FNextFreedMemBlock <> nil then
      {Self.}FNextFreedMemBlock.FPreviousFreedMemBlock := nil;

    //remove from free list
    {Self.}FPreviousFreedMemBlock := nil;
    {Self.}FNextFreedMemBlock     := nil;
  end
  //all memory was available?
//  else if FFreedIndex = CARRAYSIZE-1 then
//    dec(Owner.FFullyFreedMemListCount);
end;

///////////////////////////////////////////////////////////////////////////////
{ TMemBlockList }

procedure TMemBlockList.AddNewMemoryBlock;
var
  pm: PMemBlock;
begin
  //get block from cache
  pm := GlobalManager.GetBlockMemory(FItemSize);
  //else create own one
  if pm = nil then
  begin
    pm := Scale_AllocMem(SizeOf(pm^));
//    new(pm);
//    ZeroMemory(pm, SizeOf(TMemBlock));

    with pm^ do
    begin
      {pm.}Owner     := @Self;
      {pm.}FItemSize := Self.FItemSize;
      AllocBlockMemory;                  //init
    end;
  end;

  //init
  with pm^ do
  begin
    {pm.}Owner             := @Self;
    //set new memlist as first, add link to current item
    {pm.}FNextMemBlock     := {self}FFirstMemBlock;
    //back link to new first item
    if {self}FFirstMemBlock <> nil then
      {self}FFirstMemBlock.FPreviousMemBlock := pm;
    {self}FFirstMemBlock   := pm;
    {pm.}FPreviousMemBlock := nil;

    //if block has already some freed memory (previous used block from cache)
    //then add to used list
    if {pm.}FFreedIndex > 0 then
    begin
      {pm.}FNextFreedMemBlock     := {Self}FFirstFreedMemBlock;   //link to first list
      {pm.}FPreviousFreedMemBlock := nil;
      if {pm}FNextFreedMemBlock <> nil then
        {pm}FNextFreedMemBlock.FPreviousFreedMemBlock := pm; //back link
      {Self}FFirstFreedMemBlock   := pm;                     //replace first list
    end;
  end;
end;

function TMemBlockList.GetMemFromUsedBlock: Pointer;
begin
  Result := FFirstFreedMemBlock.GetUsedMemoryItem;
end;

function TMemBlockList.GetMemFromNewBlock: Pointer;
var
  pm: PMemBlock;
begin
  //store: first time init?
  if FFirstMemBlock = nil then
  begin
    if FRecursive then
    begin
      Result := Self.Owner.GetOldMem(Self.FItemSize);
      Exit;
    end;
    FRecursive := True;
    AddNewMemoryBlock;
    FRecursive := False;

//    if FFirstMemBlock.FUsageCount = 0 then
      //always keep at least one in buffer, so we do this cheat here...
//      inc(FFirstMemBlock.FUsageCount);
  end;

  pm := FFirstMemBlock;
  with pm^ do
  begin
    //memlist full? make new memlist
    if FUsageCount >= C_ARRAYSIZE then
    begin
      if FRecursive then
      begin
        Result := Self.Owner.GetOldMem(Self.FItemSize);
        Exit;
      end;
      FRecursive := True;
      AddNewMemoryBlock;
      FRecursive := False;

      pm := FFirstMemBlock;
    end;
  end;

  //get mem from list
  with pm^ do
  begin
    //space left?
    if FUsageCount < C_ARRAYSIZE then
    begin
      //calc next item
      Result := Pointer(NativeUInt(FMemoryArray) +
                                  ( FUsageCount *
                                   (FItemSize + SizeOf(TMemHeader))
                                  )
                       );
      inc(FUsageCount);
      //startheader = link to memlist
      TMemHeader(Result^).Owner := pm;
    end
    else
      Result := pm.GetUsedMemoryItem;
//      Result := nil;
  end;

  Assert(NativeUInt(Result) > $10000);
end;

///////////////////////////////////////////////////////////////////////////////
{ TGlobalManager }

procedure TGlobalMemManager.AddNewThreadManagerToList(aThreadMem: PThreadMemManager);
var
  pprevthreadmem: PThreadMemManager;
begin
  repeat
    pprevthreadmem := FFirstThreadMemory;
    //try to set "result" in global var
    if CAS32(pprevthreadmem, aThreadMem, FFirstThreadMemory) then
      break;
    sleep(0);
  until True = False;
  //make linked list: new one is first item (global var), next item is previous item
  aThreadMem.FNextThreadManager := pprevthreadmem;
end;

class constructor TGlobalMemManager.Create;
begin
  GlobalManager.Init;
end;

class destructor TGlobalMemManager.Destroy;
begin
  GlobalManager.FreeAllMemory;
end;

procedure TGlobalMemManager.FreeAllMemory;
var i: Byte;

  procedure __ProcessBlockMem(aOldBlock: PMemBlockList);
  var
    allmem, oldmem: PMemBlock;
  begin
    if aOldBlock = nil then Exit;

    allmem := aOldBlock.FFirstFreedMemBlock;
    while allmem <> nil do
    begin
      //not in use
      if allmem.FUsageCount = allmem.FFreedIndex then
      begin
        oldmem := allmem;
        allmem := allmem.FNextMemBlock;
        Scale_FreeMem(oldmem.FMemoryArray);
        Scale_FreeMem(oldmem);
        //Dispose(oldmem);
        //OldMM.FreeMem(oldmem);
      end
      else
        allmem := allmem.FNextMemBlock;
    end;
  end;

var
  oldthreadmem, tempthreadmem: PThreadMemManager;
begin
  //mini
  for i := Low(Self.FFreedMiniMemoryBlocks) to High(Self.FFreedMiniMemoryBlocks) do
    __ProcessBlockMem(@Self.FFreedMiniMemoryBlocks[i]);
  //small
  for i := Low(Self.FFreedSmallMemoryBlocks) to High(Self.FFreedSmallMemoryBlocks) do
    __ProcessBlockMem(@Self.FFreedSmallMemoryBlocks[i]);
  //medium
  for i := Low(Self.FFreedMediumMemoryBlocks) to High(Self.FFreedMediumMemoryBlocks) do
    __ProcessBlockMem(@Self.FFreedMediumMemoryBlocks[i]);

  //free current thread
  tempthreadmem := GetCurrentThreadManager;
  //mini
  for i := Low(tempthreadmem.FMiniMemoryBlocks) to High(tempthreadmem.FMiniMemoryBlocks) do
    __ProcessBlockMem(@tempthreadmem.FMiniMemoryBlocks[i]);
  //small
  for i := Low(tempthreadmem.FSmallMemoryBlocks) to High(tempthreadmem.FSmallMemoryBlocks) do
    __ProcessBlockMem(@tempthreadmem.FSmallMemoryBlocks[i]);
  //medium
  for i := Low(tempthreadmem.FMediumMemoryBlocks) to High(tempthreadmem.FMediumMemoryBlocks) do
    __ProcessBlockMem(tempthreadmem.FMediumMemoryBlocks[i]);

  //free cached threads
  oldthreadmem := Self.FFirstFreedThreadMemory;
  while oldthreadmem <> nil do
  begin
    tempthreadmem := oldthreadmem;
    oldthreadmem  := oldthreadmem.FNextThreadManager;
    OldMM.FreeMem(tempthreadmem);
  end;
end;

procedure TGlobalMemManager.FreeBlockMemory(aBlockMem: PMemBlock);
var i : Byte;
    bl: PMemBlockList;
    prevmem: PMemBlock;
begin
  Assert( aBlockMem.FFreedIndex = aBlockMem.FUsageCount );

  //mini block?
  with aBlockMem.Owner^ do
  begin
    if FItemSize <= 8 * 32 then
    begin
      //-1 because 32 div 32 = 1, but we want index 0!
      i  := (FItemSize-1) div 32;       //blocks of 32: 32, 64, 96, etc till 256
      bl := @Self.FFreedMiniMemoryBlocks[i]
    end
    //small block?
    else if FItemSize <= 8 * 256 then
    begin
      i  := (FItemSize-1) div 256;    //blocks of 256: 256, 512, 768, etc till 2048
      bl := @Self.FFreedSmallMemoryBlocks[i]
    end
    else
      bl := nil;
  end;

  //release large mem
  if bl = nil then
  begin
    Scale_FreeMem(aBlockMem.FMemoryArray);
    Scale_FreeMem(aBlockMem);
  end
  //add to list
  else
  begin
    { TODO -oAM : instead of locks, use fixed array[max 10] with interlocked inc/dec }

    //lock
    while bl.FRecursive or
          (LockCmpxchg(0, 1, @bl.FRecursive) <> 0)
    do
      Sleep(0);
    try
      //too much cached?
      if bl.FFreeMemCount > C_GLOBAL_BLOCK_CACHE then
      begin
        //dispose
        Scale_FreeMem(aBlockMem.FMemoryArray);
        Scale_FreeMem(aBlockMem);
        //unlock
        bl.FRecursive := False;

        Exit;
      end;

      //add freemem block to front (replace first item, link previous to firsts item)
      prevmem                          := bl.FFirstFreedMemBlock;
      aBlockMem.FNextFreedMemBlock     := prevmem;
      if prevmem <> nil then
        prevmem.FPreviousFreedMemBlock := aBlockMem;
      bl.FFirstFreedMemBlock           := aBlockMem;
      //inc items cached
      inc(bl.FFreeMemCount);
    finally
      //unlock
      bl.FRecursive := False;
    end;

    (*
    //add freemem list to front (replace first item, link previous to last item)
    repeat
      prevmem                      := bl.FFirstFreedMemBlock;
      aBlockMem.FNextFreedMemBlock := prevmem;
      if CAS32(prevmem, aBlockMem, bl.FFirstFreedMemBlock) then break;
      sleep(0);
    until True = False;
    *)

    aBlockMem.Owner                  := bl;
    //aBlockMem.FNextFreedMemBlock     := nil;
    aBlockMem.FNextMemBlock          := nil;
    aBlockMem.FPreviousMemBlock      := nil;
    aBlockMem.FPreviousFreedMemBlock := nil;
  end;
end;

procedure TGlobalMemManager.FreeBlocksFromThreadMemory(aThreadMem: PThreadMemManager);
var
  i: Byte;

  procedure __ProcessBlockMem(aOldBlock, aGlobalBlock: PMemBlockList);
  var
    allmem, prevmem, tempmem,
    lastunusedmem, lastinusemem,
    unusedmem, inusemem: PMemBlock;
  begin
    allmem        := aOldBlock.FFirstMemBlock;
    unusedmem     := nil;
    lastunusedmem := nil;
    inusemem      := nil;
    lastinusemem  := nil;

    //scan all memoryblocks and filter unused blocks
    while allmem <> nil do
    begin
      if allmem.Owner = nil then Break; //loop?

      //fully free, no mem in use?
      if allmem.FFreedIndex = allmem.FUsageCount then
      begin

        if aGlobalBlock.FFreeMemCount > C_GLOBAL_BLOCK_CACHE then
        begin
          tempmem := allmem;
          //next one
          allmem  := allmem.FNextMemBlock;

          //dispose
          Scale_FreeMem(tempmem.FMemoryArray);
          Scale_FreeMem(tempmem);
          Continue;
        end;

        //first item of list?
        if unusedmem = nil then
          unusedmem    := allmem
        //else add to list (link to previous)
        else
          lastunusedmem.FNextMemBlock := allmem;
        lastunusedmem  := allmem;

        //inc items cached
        inc(aGlobalBlock.FFreeMemCount);
      end
      else
      //some items in use (in other thread? or mem leak?)
      begin
        //first item of list?
        if inusemem = nil then
          inusemem    := allmem
        //else add to list (link to previous)
        else
          lastinusemem.FNextMemBlock := allmem;
        lastinusemem  := allmem;

        //inc items cached
        inc(aGlobalBlock.FFreeMemCount);
      end;

      allmem.Owner                  := aGlobalBlock;
      allmem.FNextFreedMemBlock     := nil;
      //allmem.FNextMemBlock          := nil;
      allmem.FPreviousMemBlock      := nil;
      allmem.FPreviousFreedMemBlock := nil;

      //next one
      allmem := allmem.FNextMemBlock;
    end;

    if inusemem <> nil then
    begin
      assert(lastinusemem <> nil);
      //add freemem list to front (replace first item, link previous to last item)
      repeat
        prevmem                         := aGlobalBlock.FFirstFreedMemBlock;
        lastinusemem.FNextFreedMemBlock := prevmem;
        if CAS32(prevmem, inusemem, aGlobalBlock.FFirstFreedMemBlock) then break;
        sleep(0);
      until True = False;
    end;

    if unusedmem <> nil then
    begin
      assert(lastunusedmem <> nil);
      //add unusedmem list to front (replace first item, link previous to last item)
      repeat
        prevmem                     := aGlobalBlock.FFirstMemBlock;
        lastunusedmem.FNextMemBlock := prevmem;
        if CAS32(prevmem, unusedmem, aGlobalBlock.FFirstMemBlock) then break;
        sleep(0);
      until True = False;
    end;
  end;

begin
  //mini
  for i := Low(aThreadMem.FMiniMemoryBlocks) to High(aThreadMem.FMiniMemoryBlocks) do
    __ProcessBlockMem( @aThreadMem.FMiniMemoryBlocks[i],   @Self.FFreedMiniMemoryBlocks[i]);
  //small
  for i := Low(aThreadMem.FSmallMemoryBlocks) to High(aThreadMem.FSmallMemoryBlocks) do
    __ProcessBlockMem( @aThreadMem.FSmallMemoryBlocks[i],  @Self.FFreedSmallMemoryBlocks[i]);
  //medium
  for i := Low(aThreadMem.FMediumMemoryBlocks) to High(aThreadMem.FMediumMemoryBlocks) do
    __ProcessBlockMem( @aThreadMem.FMediumMemoryBlocks[i], @Self.FFreedMediumMemoryBlocks[i]);
end;

procedure TGlobalMemManager.FreeThreadManager(aThreadMem: PThreadMemManager);
var
  pprevthreadmem: PThreadMemManager;
begin
  //clear mem (partial: add to reuse list, free = free)
  FreeBlocksFromThreadMemory(aThreadMem);

  aThreadMem.Reset;

  { TODO : keep max nr of threads }

  //add to available list
  repeat
    pprevthreadmem := FFirstFreedThreadMemory;
    //make linked list: new one is first item (global var), next item is previous item
    aThreadMem.FNextThreadManager := pprevthreadmem;
    //try to set "result" in global var
    if CAS32(pprevthreadmem, aThreadMem, FFirstFreedThreadMemory) then
      break;
    sleep(0);
  until True = False;
end;

function TGlobalMemManager.GetBlockMemory(aItemSize: NativeInt): PMemBlock;
var i : Byte;
    bl: PMemBlockList;
    prevmem, nextmem: PMemBlock;
begin
  Result := nil;

  //determine block
  if aItemSize <= 8 * 32 then
  begin
    //-1 because 32 div 32 = 1, but we need index 0!
    i  := (aItemSize-1) div 32;       //blocks of 32: 32, 64, 96, etc till 256
    bl := @Self.FFreedMiniMemoryBlocks[i]
  end
  //small block?
  else if aItemSize <= 8 * 256 then
  begin
    i  := (aItemSize-1) div 256;    //blocks of 256: 256, 512, 768, etc till 2048
    bl := @Self.FFreedSmallMemoryBlocks[i]
  end
  else
    Exit;

  //lock
  while bl.FRecursive or
        (LockCmpxchg(0, 1, @bl.FRecursive) <> 0)
  do
    Sleep(0);
  try
    //get freed mem from list from front (replace first item)
    if bl.FFirstFreedMemBlock <> nil then
    begin
      prevmem  := bl.FFirstFreedMemBlock;
      nextmem  := prevmem.FNextFreedMemBlock;
      bl.FFirstFreedMemBlock := nextmem;
      if nextmem <> nil then
        nextmem.FPreviousFreedMemBlock := nil;
      Result := prevmem;
    end
    //get free mem from list from front (replace first item)
    else if bl.FFirstMemBlock <> nil then
    begin
      prevmem  := bl.FFirstMemBlock;
      nextmem  := prevmem.FNextMemBlock;
      bl.FFirstMemBlock := nextmem;
      if nextmem <> nil then
        nextmem.FPreviousMemBlock := nil;
      Result := prevmem;
    end;
  finally
    //unlock
    bl.FRecursive := False;
  end;

  {
  //get freemem from list from front (replace first item)
  while (bl.FFirstFreedMemBlock <> nil) do
  begin
    prevmem  := bl.FFirstFreedMemBlock;
    if prevmem <> nil then
      nextmem  := prevmem.FNextFreedMemBlock;
    if CAS32(prevmem, nextmem, bl.FFirstFreedMemBlock) then
    begin
      if nextmem <> nil then
        nextmem.FPreviousFreedMemBlock := nil;
      Result := prevmem;
      break;
    end;
    sleep(0);
  end;
  }

  if Result <> nil then
  begin
    dec(bl.FFreeMemCount);

    Result.Owner                  := bl;
    Result.FNextFreedMemBlock     := nil;
    Result.FNextMemBlock          := nil;
    Result.FPreviousMemBlock      := nil;
    Result.FPreviousFreedMemBlock := nil;
  end;
end;

function TGlobalMemManager.GetNewThreadManager: PThreadMemManager;
var
  pprevthreadmem, newthreadmem: PThreadMemManager;
begin
  Result := nil;

  //get from list
  while FFirstFreedThreadMemory <> nil do
  begin
    pprevthreadmem := FFirstFreedThreadMemory;
    if pprevthreadmem <> nil then
      newthreadmem   := pprevthreadmem.FNextThreadManager
    else
      newthreadmem   := nil;
    //try to set "result" in global var
    if CAS32(pprevthreadmem, newthreadmem, FFirstFreedThreadMemory) then
    begin
      Result := pprevthreadmem;
      Result.FNextThreadManager := nil;
      break;
    end;
    sleep(0);
  end;
end;

procedure TGlobalMemManager.Init;
var i: Byte;
//    mainthreadmem: PThreadMemManager;
begin
  //init mini
  for i := Low(FFreedMiniMemoryBlocks) to High(FFreedMiniMemoryBlocks) do
  begin
    FFreedMiniMemoryBlocks[i].Owner               := @Self;
    FFreedMiniMemoryBlocks[i].FFirstMemBlock      := nil;
    FFreedMiniMemoryBlocks[i].FFirstFreedMemBlock := nil;
    FFreedMiniMemoryBlocks[i].FItemSize           := (i+1) * 32;
  end;

  //init small
  for i := Low(FFreedSmallMemoryBlocks) to High(FFreedSmallMemoryBlocks) do
  begin
    FFreedSmallMemoryBlocks[i].Owner               := @Self;
    FFreedSmallMemoryBlocks[i].FFirstMemBlock      := nil;
    FFreedSmallMemoryBlocks[i].FFirstFreedMemBlock := nil;
    FFreedSmallMemoryBlocks[i].FItemSize           := (i+1) * 256;
  end;

//  RegisterExpectedMemoryLeak(@Self);
//  RegisterExpectedMemoryLeak(mainthreadmem);
end;

///////////////////////////////////////////////////////////////////////////////

function Scale_ReallocMem(aMemory: Pointer; aSize: Integer): Pointer;
var
  pm: PMemBlock;
  p: Pointer;
begin
  // ReAlloc can be misued as GetMem or FreeMem (documented in delphi help) so check what the user wants
  Assert(NativeUInt(aMemory) > $10000);

  // Normal realloc of exisiting data?
  if (aMemory <> nil) and (aSize > 0) then
  begin
    p  := Pointer(NativeUInt(aMemory) - SizeOf(TMemHeader));
    pm := PMemHeader(p).Owner;

    if pm <> nil then
    with pm^ do
    begin
      //new size smaller then current size?
      if (aSize <= Owner.FItemSize) then    //we have already incremented blocksize in "TMemList.AllocMem" and "TMemStore.GetMemFromList"
      begin
        //if (aSize + Owner.FItemSize >= Owner.FItemSize) then
        //if aSize >= (Owner.FItemSize div 2) then
        if aSize >= (Owner.FItemSize shr 1) then
          Result := aMemory //no resize needed
        else
        //too much downscaling
        begin
          Result := Scale_GetMem(aSize);   //new mem
          if aMemory <> Result then
          begin
            Move(aMemory^, Result^,
                 aSize);                   //copy (use smaller new size)
            Scale_FreeMem(aMemory);        //free old mem
          end;
        end;
      end
      else
      //new size bigger then current size?
      begin
        Result := Scale_GetMem(aSize);     //new mem
        if aMemory <> Result then
        begin
          Move(aMemory^, Result^,
               Owner.FItemSize);    //copy (use smaller old size)
          Scale_FreeMem(aMemory);          //free old mem
        end;
      end;
    end
    //oldmm
    else
    begin
      Result := OldMM.ReallocMem(p, aSize + SizeOf(TMemHeader));
      TMemHeader(Result^).Owner := nil;  //not our memlist, so nil, so we can check on this
      Result := Pointer(NativeUInt(Result) + SizeOf(TMemHeader) );
    end;
  end
  else
  begin
    if (aMemory = nil) and (aSize > 0) then
    begin // GetMem disguised as ReAlloc
      Result := Scale_GetMem(aSize);
    end
    else
    begin // FreeMem disguised as ReAlloc
      Result := nil;
      Scale_FreeMem(aMemory);
    end;
  end;
end;

function Scale_GetMem(aSize: Integer): Pointer;
begin
  Result := GetSmallMemManager.GetMem(aSize);
  Assert(NativeUInt(Result) > $10000);
end;

function Scale_AllocMem(aSize: Cardinal): Pointer;
begin
  Result := GetSmallMemManager.GetMem(aSize);
  Assert(NativeUInt(Result) > $10000);
  ZeroMemory(Result, aSize);
end;

function Scale_FreeMem(aMemory: Pointer): Integer;
begin
  Assert(NativeUInt(aMemory) > $10000);
  Result := GetSmallMemManager.FreeMem(aMemory);
end;

function Scale_RegisterMemoryLeak(P: Pointer): Boolean;
begin
  { TODO : implement memory leak checking }
  Result := OldMM.RegisterExpectedMemoryLeak(p);
end;

function Scale_UnregisterMemoryLeak(P: Pointer): Boolean;
begin
  Result := OldMM.UnregisterExpectedMemoryLeak(p);
end;

{$REGION 'ThreadHooks'}
type
  TEndThread = procedure(ExitCode: Integer);
var
  OldEndThread: TEndThread;

procedure NewEndThread(ExitCode: Integer); //register; // ensure that calling convension matches EndThread
begin
  //free all thread mem
  GlobalManager.FreeThreadManager( GetCurrentThreadManager );
  //OldEndThread(ExitCode);  todo: make trampoline with original begin etc
  //code of original EndThread;
  ExitThread(ExitCode);
end;

type
  PJump = ^TJump;
  TJump = packed record
    OpCode: Byte;
    Distance: Integer;
  end;
var
  //OldCode: TJump;
  NewCode: TJump = (OpCode  : $E9;
                    Distance: 0);

// redirect calls to System.EndThread to NewEndThread
procedure PatchThread;
var
  pEndThreadAddr: PJump;
  iOldProtect: DWord;
begin
  pEndThreadAddr   := Pointer(@EndThread);
  Scale_VirtualProtect(pEndThreadAddr, 5, PAGE_EXECUTE_READWRITE, iOldProtect);
  //calc jump to new function
  NewCode.Distance := Cardinal(@NewEndThread) - (Cardinal(@EndThread) + 5);
  //store old
  OldEndThread     := TEndThread(pEndThreadAddr);
  //overwrite with jump to new function
  pEndThreadAddr^  := NewCode;
  //flush CPU
  FlushInstructionCache(GetCurrentProcess, pEndThreadAddr, 5);
end;
{$ENDREGION ThreadHooks}

{
procedure TestSize;
var
  iSize: integer;
begin
  iSize := SizeOf(TMemHeader);         //8
  iSize := SizeOf(TMemBlock);          //232    size 32*50 = 1600 bytes
                                       //       232 + 50*8 =  632       => 39% overhead
                                       //       size 256 * 50 = 12800
                                       //       232 + 50*8    =   632   =>  4% overhead
  iSize := SizeOf(TMemBlockList);      //24
  iSize := SizeOf(TThreadMemManager);  //704
end;
}

const
  ScaleMM_Ex: TMemoryManagerEx = (
    GetMem                      : Scale_GetMem;
    FreeMem                     : Scale_FreeMem;
    ReallocMem                  : Scale_ReallocMem;
    AllocMem                    : Scale_AllocMem;
    RegisterExpectedMemoryLeak  : Scale_RegisterMemoryLeak;
    UnregisterExpectedMemoryLeak: Scale_UnregisterMemoryLeak);

procedure ScaleMMInstall;
begin
  {$IFnDEF PURE_PASCAL}
  //get TLS slot
  GOwnTlsIndex  := TlsAlloc;
  //write fixed offset to TLS slot (instead calc via GOwnTlsIndex)
  _FixedOffset;
  {$ENDIF}

  // Hook memory Manager
  GetMemoryManager(OldMM);
  if @OldMM <> @ScaleMM_Ex then
    SetMemoryManager(ScaleMM_Ex);

  //init main thread manager
  GlobalManager.FMainThreadMemory := GetCurrentThreadManager;
end;

initialization
  ScaleMMInstall;
  PatchThread;

finalization
  { TODO : check for memory leaks }
  Sleep(0);        //dummy for breakpoint

end.


