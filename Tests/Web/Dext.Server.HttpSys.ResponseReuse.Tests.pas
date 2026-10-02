unit Dext.Server.HttpSys.ResponseReuse.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Server.HttpSys;

type
  /// <summary>
  ///   TDextHttpSysResponse objects are pooled and reused through Init. A body
  ///   larger than 32 segments makes the response writer grow its segment
  ///   table with GetMem; reusing the response must release that table, as
  ///   the destructor does. No HTTP.sys call is made: until the headers are
  ///   sent the body stays in the writer.
  /// </summary>
  [TestFixture('HTTP.sys - reusing a response object')]
  THttpSysResponseReuseTests = class
  public
    [Test('Should not leak the grown segment table when a response is reused')]
    procedure TestReuseReleasesTheGrownSegmentTable;
  end;

implementation

// Small blocks are not counted: the grown table is a medium block, and small
// ones come and go with everything else running in the process.
function MediumAndLargeBlocks: Integer;
var
  State: TMemoryManagerState;
begin
  GetMemoryManagerState(State);
  Result := State.AllocatedMediumBlockCount + State.AllocatedLargeBlockCount;
end;

{ THttpSysResponseReuseTests }

procedure THttpSysResponseReuseTests.TestReuseReleasesTheGrownSegmentTable;
const
  // 1 MB = 256 segments of 4 KB: the segment table grows to 256 entries,
  // 8 KB, which is a medium block.
  BodySize = 1024 * 1024;
  Rounds = 5;
var
  Response: TDextHttpSysResponse;
  Body: TBytes;
  I, Before, After: Integer;
begin
  SetLength(Body, BodySize);
  FillChar(Body[0], BodySize, Ord('x'));
  Response := TDextHttpSysResponse.Create(nil, 0, 0);
  try
    // Two warm-up rounds: the segment pool reaches its steady size.
    for I := 1 to 2 do
    begin
      Response.Write(Body, 0, BodySize);
      Response.Init(nil, 0, 0);
    end;
    Before := MediumAndLargeBlocks;
    for I := 1 to Rounds do
    begin
      Response.Write(Body, 0, BodySize);
      Response.Init(nil, 0, 0);
    end;
    After := MediumAndLargeBlocks;
  finally
    Response.Free;
  end;

  Should(After - Before).Be(0)
    .Because('each reuse used to lose the grown segment table (one medium ' +
      'block per response larger than 32 segments)');
end;

end.
