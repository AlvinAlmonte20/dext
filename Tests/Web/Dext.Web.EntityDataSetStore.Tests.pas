unit Dext.Web.EntityDataSetStore.Tests;

interface

uses
  System.SysUtils,
  System.Variants,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Collections,
  Dext.Json,
  Dext.Json.Types,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.FireDAC,
  Dext.Web.EntityDataSetApi,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt;

type
  {$M+}
  [Table('eds_items')]
  TEdsItem = class
  private
    FCode: string;
    FName: string;
  public
    [PK, Column('code')]
    property Code: string read FCode write FCode;
    [Column('name')]
    property Name: string read FName write FName;
  end;
  {$M-}

  /// <summary>
  ///   TDbContextEntityDataSetStore.ApplyChanges against a real SQLite
  ///   database: eds_items.name is UNIQUE, and the row ('s1', 'seed') is there
  ///   before every test, so inserting the name 'seed' again makes an item fail.
  ///   The key is a string: the store passes every key and value as a string
  ///   (see the PR notes about non-string properties).
  /// </summary>
  [TestFixture('EntityDataSet store - ApplyChanges atomicity')]
  TEntityDataSetStoreTests = class
  private
    FConn: TFDConnection;
    FContext: TDbContext;
    function Apply(const AJson: string;
      AContinueOnError: Boolean = False): IList<TApplyItemResult>;
    function RowCount(const AName: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test('Should apply nothing when one item of the batch fails')]
    procedure TestFailingItemRollsBackTheWholeBatch;

    [Test('Should report every item of a failed batch as not applied')]
    procedure TestFailedBatchReportsEveryItem;

    [Test('Should leave nothing tracked after a failed batch')]
    procedure TestFailedBatchLeavesTheContextClean;

    [Test('Should apply inserts, updates and deletes together and return the new keys')]
    procedure TestSuccessfulBatchAppliesEverything;

    [Test('Should keep the other items when ContinueOnError is set')]
    procedure TestContinueOnErrorKeepsTheOtherItems;

    [Test('Should not retry a failed item on the next SaveChanges with ContinueOnError')]
    procedure TestContinueOnErrorDoesNotRetryTheFailedItem;
  end;

implementation

{ TEntityDataSetStoreTests }

procedure TEntityDataSetStoreTests.Setup;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  FConn.ExecSQL('CREATE TABLE eds_items (code VARCHAR(20) PRIMARY KEY, ' +
    'name VARCHAR(50) NOT NULL UNIQUE)');
  FConn.ExecSQL('INSERT INTO eds_items (code, name) VALUES (''s1'', ''seed'')');

  FContext := TDbContext.Create(TFireDACConnection.Create(FConn, False),
    TSQLiteDialect.Create);
  // Registers the DbSet, as a typed context property would.
  FContext.Entities<TEdsItem>;
end;

procedure TEntityDataSetStoreTests.TearDown;
begin
  FreeAndNil(FContext);
  FreeAndNil(FConn);
end;

function TEntityDataSetStoreTests.Apply(const AJson: string;
  AContinueOnError: Boolean): IList<TApplyItemResult>;
var
  Store: IEntityDataSetStore;
  Changes: IDextJsonArray;
begin
  Store := TDbContextEntityDataSetStore.Create(AContinueOnError);
  Changes := (TDextJson.Provider.Parse(AJson) as IDextJsonObject).GetArray('changes');
  Result := Store.ApplyChanges(TEdsItem, Changes, FContext);
end;

function TEntityDataSetStoreTests.RowCount(const AName: string): Integer;
begin
  Result := FConn.ExecSQLScalar('SELECT COUNT(*) FROM eds_items WHERE name = :n',
    [AName]);
end;

procedure TEntityDataSetStoreTests.TestFailingItemRollsBackTheWholeBatch;
begin
  Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"b1","Name":"b"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}');

  Should(RowCount('a')).Be(0)
    .Because('item 2 failed, so item 0 must not be committed');
  Should(RowCount('b')).Be(0);
  Should(RowCount('seed')).Be(1);
end;

procedure TEntityDataSetStoreTests.TestFailedBatchReportsEveryItem;
var
  Results: IList<TApplyItemResult>;
  I: Integer;
begin
  Results := Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}');

  Should(Results.Count).Be(2);
  for I := 0 to Results.Count - 1 do
  begin
    Should(Results[I].Success).BeFalse;
    Should(Results[I].ErrorMessage).NotBeEmpty;
  end;
end;

procedure TEntityDataSetStoreTests.TestFailedBatchLeavesTheContextClean;
begin
  Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}');

  Should(FContext.ChangeTracker.HasChanges).BeFalse
    .Because('a later SaveChanges on the same context must not retry the batch');
end;

procedure TEntityDataSetStoreTests.TestSuccessfulBatchAppliesEverything;
var
  Results: IList<TApplyItemResult>;
  NewKey: Variant;
begin
  FConn.ExecSQL('INSERT INTO eds_items (code, name) VALUES (''o1'', ''old'')');

  Results := Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"modified","key":{"Code":"s1"},"values":{"Name":"seed2"}},' +
    '{"state":"deleted","key":{"Code":"o1"}}]}');

  Should(Results.Count).Be(3);
  Should(Results[0].ErrorMessage).BeEmpty;
  Should(Results[1].ErrorMessage).BeEmpty;
  Should(Results[2].ErrorMessage).BeEmpty;
  Should(Results[0].Success).BeTrue;
  Should(Results[1].Success).BeTrue;
  Should(Results[2].Success).BeTrue;

  Should(RowCount('a')).Be(1);
  Should(RowCount('seed2')).Be(1);
  Should(RowCount('seed')).Be(0);
  Should(RowCount('old')).Be(0);

  Should(Results[0].Keys <> nil).BeTrue;
  Should(Results[0].Keys.TryGetValue('Code', NewKey)).BeTrue;
  Should(string(NewKey)).Be('a1');
end;

procedure TEntityDataSetStoreTests.TestContinueOnErrorKeepsTheOtherItems;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}},' +
    '{"state":"inserted","values":{"Code":"c1","Name":"c"}}]}', True);

  Should(Results[0].Success).BeTrue;
  Should(Results[1].Success).BeFalse;
  Should(Results[2].Success).BeTrue
    .Because('the failed item must not drag the next one down with it');
  Should(RowCount('a')).Be(1);
  Should(RowCount('c')).Be(1);
end;

procedure TEntityDataSetStoreTests.TestContinueOnErrorDoesNotRetryTheFailedItem;
begin
  Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}', True);

  Should(FContext.ChangeTracker.HasChanges).BeFalse
    .Because('the failed entity must be detached, not left as Added');
end;

end.
