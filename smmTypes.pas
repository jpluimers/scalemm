unit smmTypes;

interface

{$Include smmOptions.inc}

type
  {$if CompilerVersion <= 20}
  // from Delphi 6 up to Delphi 2007
  // also for 2009: http://code.google.com/p/scalemm/issues/detail?id=1
  NativeUInt = Cardinal;
  NativeInt  = Integer;
  {$ifend}

  PBaseMemHeader     = ^TBaseMemHeader;
  PBaseFreeMemHeader = ^TBaseFreeMemHeader;
  PBaseBlockMemory   = ^TBaseBlockMemory;
  PBaseSizeManager   = ^TBaseSizeManager;
  PBaseThreadManager = ^TBaseThreadManager;
  PBaseThreadManagerOffset = ^TBaseThreadManagerOffset;

  TBaseMemHeader = object
    {$IFDEF SCALEMM_MAGICTEST}
    Magic1     : NativeInt;
    Magic2     : NativeInt;  //8byte aligned
    {$ELSE}
      {$IFDEF Align16Bytes}
        {$ifndef CPUX64}
        Filer1: Pointer;  // 16 bytes aligned for 32 bit compiler
        Filer2: Pointer;
        {$endif}
      {$ENDIF}
    {$ENDIF}

    //small, medium and large mem can add extra stuff IN FRONT
    Size : NativeUInt;
    //must be last of "universal" header!
    OwnerBlock: PBaseBlockMemory;
  end;

  TBaseFreeMemHeader = object
    {$IFDEF SCALEMM_MAGICTEST}
    Magic1     : NativeInt;
    Magic2     : NativeInt;  //8byte aligned
    {$ELSE}
      {$IFDEF Align16Bytes}
        {$ifndef CPUX64}
        Filer1: Pointer;  // 16 bytes aligned for 32 bit compiler
        Filer2: Pointer;
        {$endif}
      {$ENDIF}
    {$ENDIF}

    //small, medium and large mem can add extra stuff IN FRONT
    Size  : NativeUInt;
    OwnerBlock : PBaseBlockMemory;

    //Extra data of free item:---------------------------------
    NextThreadFree: PBaseFreeMemHeader;  //linked list of interthread memory
  end;

  TSizeType = (stSmall, stMedium, stLarge);

  TBaseBlockMemory = object
    //SizeType   : TSizeType;
    OwnerManager: PBaseSizeManager;
    //small, medium and large mem can add extra stuff BEHIND
  end;

  TBaseSizeManager = object
    SizeType    : TSizeType;
    OwnerThread: PBaseThreadManager;
    //small, medium and large mem can add extra stuff BEHIND
  end;

  TBaseThreadManagerOffset = packed
                             {$if CompilerVersion >= 18} //Delphi 2007 and higher?
                             record {$ELSE} object {$ifend}
  public
    //FOtherThreadFreedMemory: PBaseFreeMemHeader;
    //Filler0: Byte;   //1 or 2 (lowest bits) = medium or large
    Filler1, Filler2, Filler3: Byte;  //offset of 1 to distinguish of being medium or large block
    FOtherThreadFreeLock: LongBool;

    FThreadId: LongWord;
    FThreadTerminated: LongBool;
    //extra stuff BEHIND
  end;

  TBaseThreadManager = object
    FOtherThreadFreedMemory: PBaseFreeMemHeader;
    FOtherThreadFreeLock: Boolean;

    FThreadId: LongWord;
    FThreadTerminated: Boolean;
    //extra stuff BEHIND
  end;

  TScanDirection = (sdNone, sdPrevious, sdNext, sdBoth);

implementation

initialization
  {$IFDEF Align8Bytes}
  Assert( SizeOf(TBaseMemHeader) AND 7 = 0);
  {$ENDIF}
  {$IFDEF Align16Bytes}
  Assert( SizeOf(TBaseMemHeader) AND 15 = 0);
  {$ENDIF}

end.
