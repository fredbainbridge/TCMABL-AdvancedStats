
Function Invoke-FBAzureSubscription {
	#This will require interaction if not currently logged in. 
	#using pscredential usually wont work here.
	[CmdletBinding()]
	param(
		[string]$SubscriptionID
	)
	try 
    {
        Get-AzureRmSubscription
    }
    catch{  $loginNeeded = $true  }

    if($loginNeeded)  #not logged in
	{
		Login-AzureRmAccount 
	}	
	Select-AzureRmSubscription -SubscriptionId $SubscriptionID
}

Function Invoke-FBDeploymentSwap{
	$parameterObject = @{targetSlot = "production"} 
	Invoke-AzureRmResourceAction -ResourceGroupName "TCMABL-Dev" -ResourceType Microsoft.Web/sites/slots -ResourceName "TCMABL/tcmabl-tcmabldev" -Parameters $parameterObject -Action slotswap -ApiVersion 2015-07-01
}

#upload csv file
<#
$ResourceGroupName = 'PUBLICSTUFF'
$storageAccountName = 'fredbainbridge'
$storageContainerName = 'tcmabl'

$storageAccountKey = (Get-AzureRMStorageAccountKey -StorageAccountName $storageAccountName -ResourceGroupName $ResourceGroupName).Key1 
$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey 
#Set-AzureStorageBlobContent -File "C:\Users\fbain\Documents\PlayerCareer.csv" -Container $storageContainerName -Blob "PlayerCareers.csv" -Context $storageContext -Force
Set-AzureStorageBlobContent -File "C:\Users\fbain\Documents\TCMABLGames.csv" -Container $storageContainerName -Blob "Games.csv" -Context $storageContext -Force
#>

#Azure funny business here.

#Drop Existing Tables
Function Get-FBDatabaseReference {
	[CmdletBinding()]
	[OutputType([System.Data.SqlClient.SqlConnection])]
	param(
		[string]$ConnectionString
	)
	$SQLConnection = New-Object System.Data.SqlClient.SqlConnection
	$SQLConnection.ConnectionString = $ConnectionString
	$SQLConnection.Open()

	Write-Output $SQLConnection
}

Function Remove-FBTables {
	[CmdletBinding()]
	Param (
		[string[]] $Tables = ("Game","PlayerCareer","SeasonAverage","__MigrationHistory"),		
        [System.Data.SqlClient.SqlConnection]$SQLConnection,
        [string]$schema = "dbo"
    )
	if($SQLConnection.State -ne "Open")
    {
        $SQLConnection.Open()
    }

	$Tables | ForEach-Object {
		$Query = 
@"
            IF (EXISTS (SELECT * 
                 FROM INFORMATION_SCHEMA.TABLES 
                 WHERE TABLE_SCHEMA = '$schema' 
                 AND  TABLE_NAME = '$PSITEM'))
            BEGIN
                DROP TABLE $PSITEM
            END
"@

		$SQLCmd = New-Object System.Data.SqlClient.SqlCommand
		$SQLCmd.Connection = $SQLConnection
		$SQLCmd.CommandText = $Query
		Write-Verbose "Removing table $PSITEM if it exists"
        $x = $sqlCmd.ExecuteNonQuery() 
        
        
	}
}
#Create Tables
Function Create-FBTables {
    [CmdletBinding()]
	Param (
		[System.Data.SqlClient.SqlConnection]$SQLConnection        
    )
    $Game = 
@"
    CREATE TABLE [dbo].[Game] (
        [ID]     INT            IDENTITY (1, 1) NOT NULL,
        [Season] NVARCHAR (MAX) NULL,
        [GameID] INT            NOT NULL,
        [Team1]  NVARCHAR (MAX) NULL,
        [Score1] INT NULL,
        [Team2]  NVARCHAR (MAX) NULL,
        [Score2] INT NULL
    );

"@
$PlayerCareer = 
@" 
    CREATE TABLE [dbo].[PlayerCareer] (
        [ID]               INT            IDENTITY (1, 1) NOT NULL,
        [Number]           NVARCHAR (MAX) NULL,
        [Name]             NVARCHAR (MAX) NULL,
        [Team]             NVARCHAR (MAX) NULL,
        [Season]           NVARCHAR (MAX) NULL,
        [GameType]         NVARCHAR (MAX) NULL,
        [League]           NVARCHAR (MAX) NULL,
        [TCMABLID]         INT            NOT NULL,
        [GamesPlayed]      INT            NOT NULL,
        [PlateAppearances] INT            NOT NULL,
        [AtBats]           INT            NOT NULL,
        [Runs]             INT            NOT NULL,
        [Hits]             INT            NOT NULL,
        [Doubles]          INT            NOT NULL,
        [Triples]          INT            NOT NULL,
        [HomeRuns]         INT            NOT NULL,
        [RunsBattedIn]     INT            NOT NULL,
        [HitByPitch]       INT            NOT NULL,
        [BaseOnBalls]      INT            NOT NULL,
        [StrikeOuts]       INT            NOT NULL,
        [SacBunts]         INT            NOT NULL,
        [SacFlys]          INT            NOT NULL,
        [StolenBases]      INT            NOT NULL,
        [CaughtStealing]   INT            NOT NULL
    );
"@
$SeasonAverage = 
@"
    CREATE TABLE [dbo].[SeasonAverage] (
        [ID]                 INT             IDENTITY (1, 1) NOT NULL,
        [Season]             NVARCHAR (MAX)  NULL,
        [AverageRunsPerGame] DECIMAL (18, 2) NOT NULL,
        [AverageRunsPerTeam] DECIMAL (18, 2) NOT NULL,
        [AveragewOBA]        DECIMAL (18, 2) NOT NULL
    );

"@

    if($SQLConnection.State -ne "Open")
    {
        $SQLConnection.Open()
    }
    $SQLCmd = New-Object System.Data.SqlClient.SqlCommand
    $SQLCmd.Connection = $SQLConnection
    ($Game, $PlayerCareer, $SeasonAverage) | ForEach-Object {
        Write-Verbose "Executing `n $PSITEM"
        $SQLCmd.CommandText = $PSItem
        $null = $sqlCmd.ExecuteNonQuery()
    }
}


#populate tables.
function Update-FBPlayerCareer {
    [CmdletBinding()]
	Param (
		[System.Data.SqlClient.SqlConnection]$SQLConnection        
    )
<#
if(Test-Path 'C:\Users\fbain\Source\Workspaces\TCMABL\TCMABLModule\Player\bin\Debug\Player.dll')
{
	Import-Module 'C:\Users\fbain\Source\Workspaces\TCMABL\TCMABLModule\Player\bin\Debug\Player.dll'
}
if(Test-Path C:\Modules\User\TCMABL\Player.dll)
{
	Import-Module C:\Modules\User\TCMABL\Player.dll
}
#>

    
    $SQLConnection.Open()
    $SQLCmd = New-Object System.Data.SqlClient.SqlCommand
    $SQLCmd.Connection = $SQLConnection
    $Text = 
@"
CREATE PROCEDURE [dbo].[AddPlayer]
	@Number VARCHAR(MAX),
	@Name VARCHAR(MAX),
	@Team VARCHAR(MAX),
	@Season VARCHAR(MAX),
	@GameType VARCHAR(MAX),
	@League VARCHAR(MAX),
	@TCMABLID INT,
	@GamesPlayed INT,
	@PlateAppearances INT,
	@AtBats INT,
	@Runs INT,
	@Hits INT,
	@Doubles INT,
	@Triples INT,
	@HomeRuns INT,
	@RunsBattedIn INT,
	@HitByPitch INT,
	@BaseOnBalls INT,
	@StrikeOuts INT,
	@SacBunts INT,
	@SacFlys INT,
	@StolenBases INT,
	@CaughtStealing INT	
AS
	DECLARE @Count INT;
--
	SELECT @Count = count(TCMABLID) FROM PlayerCareer WHERE TCMABLID = @TCMABLID AND Season = @Season AND GameType = @GameType AND League = @League
	
	IF @Count = 0
	BEGIN
		INSERT INTO PlayerCareer 
		VALUES (@Number, @Name, @Team, @Season, @GameType, @League, @TCMABLID, @GamesPlayed, @PlateAppearances, @AtBats, @Runs, @Hits, 
		@Doubles, @Triples, @HomeRuns, @RunsBattedIn, @HitByPitch, @BaseOnBalls, @StrikeOuts, @SacBunts, 
		@SacFlys, @StolenBases, @CaughtStealing)
	END
	ELSE
	BEGIN
		UPDATE PlayerCareer 
		SET
		GamesPlayed = @GamesPlayed,
		PlateAppearances = @PlateAppearances	,
		AtBats = @AtBats	,
		Runs = @Runs	,
		Hits = @Hits	,
		Doubles =(@Doubles) ,
		HomeRuns = (@HomeRuns),
		RunsBattedIn = @RunsBattedIn,
		HitByPitch = @HitByPitch,
		BaseOnBalls = @BaseOnBalls,
		StrikeOuts = @StrikeOuts,
		SacBunts = @SacBunts,
		SacFlys = @SacFlys	,
		StolenBases = @StolenBases	,
		CaughtStealing = @CaughtStealing
		WHERE TCMABLID = @TCMABLID AND Season = @Season AND GameType = @GameType AND League = @League
	END

"@	

    $SQLCmd.CommandText = $Text
    $result = $sqlCmd.ExecuteNonQuery()
	
#get the player data
$url = "https://fredbainbridge.blob.core.windows.net/tcmabl/PlayerCareers.csv"
$wc = new-object system.net.WebClient
$webpage = $wc.DownloadData($url)
$string = ([System.Text.Encoding]::ASCII.GetString($webpage)).Split("`r`n") | ? {$_}	
$Player = [TCMABL.Player]::new()
$string | ForEach-Object {
	$stats = $PSITEM -split ","
	if($stats.count -eq 25)
	{
		$player.Number = $stats[1]
		$player.Name = ($stats[2])+","+($stats[3])
		$player.Team = $stats[4]
		$player.Season = $stats[5]
		$player.GameType = $stats[6]
		$player.League = $stats[7]
		$player.TCMABLID = $stats[8]
		$player.GamesPlayed = $stats[9]
		$player.PlateAppearances = $stats[10]
		$player.AtBats = $stats[11]
		$player.Runs = $stats[12]
		$player.Hits = $stats[13]
		$player.Doubles = $stats[14]
		$player.Triples = $stats[15]
		$player.HomeRuns = $stats[16]
		$player.RunsBattedIn = $stats[17]
		$player.HitByPitch = $stats[18]
		$player.BaseOnBalls = $stats[19]
		$player.StrikeOuts =  $stats[20]
		$player.SacBunts =  $stats[21]
		$player.SacFlys = $stats[22]
		$player.StolenBases = $stats[23]
		$player.CaughtStealing = $stats[24]
	}		
	#call the new stored procedure with player data.
	$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
	$SqlCmd.Connection = $SQLConnection
	$SqlCmd.CommandText = "EXEC AddPlayer @Number, @Name, @Team, @Season, @GameType, @League, @TCMABLID, @GamesPlayed, @PlateAppearances, @AtBats, @Runs, @Hits, `
	@Doubles, @Triples, @HomeRuns, @RunsBattedIn, @HitByPitch, @BaseOnBalls, @StrikeOuts, @SacBunts, @SacFlys, @StolenBases, @CaughtStealing"
	$SqlCmd.Parameters.AddWithValue("@Number", $Player.Number)	| out-null
	$SqlCmd.Parameters.AddWithValue("@Name", $Player.Name) | out-null
	$SqlCmd.Parameters.AddWithValue("@Team", $Player.Team) | out-null
	$SqlCmd.Parameters.AddWithValue("@Season", $Player.Season) | out-null
	$SqlCmd.Parameters.AddWithValue("@GameType", $Player.GameType) | out-null
	$SqlCmd.Parameters.AddWithValue("@League", $Player.League) | out-null
	$SqlCmd.Parameters.AddWithValue("@TCMABLID", $Player.TCMABLID) | out-null
	$SqlCmd.Parameters.AddWithValue("@GamesPlayed", $Player.GamesPlayed) | out-null
	$SqlCmd.Parameters.AddWithValue("@PlateAppearances", $Player.PlateAppearances) | out-null
	$SqlCmd.Parameters.AddWithValue("@AtBats", $Player.AtBats) | out-null
	$SqlCmd.Parameters.AddWithValue("@Runs", $Player.Runs) | out-null
	$SqlCmd.Parameters.AddWithValue("@Hits", $Player.Hits) | out-null
	$SqlCmd.Parameters.AddWithValue("@Doubles", $Player.Doubles) | out-null
	$SqlCmd.Parameters.AddWithValue("@Triples", $Player.Triples) | out-null
	$SqlCmd.Parameters.AddWithValue("@HomeRuns", $Player.HomeRuns) | out-null
	$SqlCmd.Parameters.AddWithValue("@RunsBattedIn", $Player.RunsBattedIn) | out-null
	$SqlCmd.Parameters.AddWithValue("@HitByPitch", $Player.HitByPitch) | out-null
	$SqlCmd.Parameters.AddWithValue("@BaseOnBalls", $Player.BaseOnBalls) | out-null
	$SqlCmd.Parameters.AddWithValue("@StrikeOuts", $Player.StrikeOuts)| out-null
	$SqlCmd.Parameters.AddWithValue("@SacBunts", $Player.SacBunts)| out-null
	$SqlCmd.Parameters.AddWithValue("@SacFlys", $Player.SacFlys)| out-null
	$SqlCmd.Parameters.AddWithValue("@StolenBases", $Player.StolenBases)| out-null
	$SqlCmd.Parameters.AddWithValue("@CaughtStealing", $Player.CaughtStealing)| out-null
	Write-Host "Adding " + $Player.Name
	$result = $sqlCmd.ExecuteReader()
	$result.Close()
}


}

function Update-FBGames {
	$ConnectionString = "Server=tcp:tcmablsqlsrv.database.windows.net,1433;Database=TCMABL-DEV;User ID=fred@tcmablsqlsrv;Password=Rival420!;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
	$SQLConnection = New-Object System.Data.SqlClient.SqlConnection
	$SQLConnection.ConnectionString = $ConnectionString
	Write-Output $SQLConnection

	$SQLConnection.Open()
	$SQLCmd = New-Object System.Data.SqlClient.SqlCommand
	$SQLCmd.Connection = $SQLConnection
	
	$url = "https://fredbainbridge.blob.core.windows.net/tcmabl/Games.csv"
	$wc = new-object system.net.WebClient
	$webpage = $wc.DownloadData($url)
	$string = ([System.Text.Encoding]::ASCII.GetString($webpage)).Split("`r`n") | ? {$_}	
	$string | ForEach-Object {
		$stats = $PSITEM -split ","
		if($stats.count -eq 6)
		{
			$Season = $stats[0]
			$TCMABLID= $stats[1]
			$Team1= $stats[2]
			$Score1= $stats[3]
			$Team2= $stats[4]
			$Score2= $stats[5]
			$Query = "Insert into Game (Season, GameID, Team1, Score1, Team2, Score2) values ('$Season',$TCMABLID,'$Team1',$Score1,'$Team2',$Score2)"
			$SqlCmd.CommandText = $query
			$result = $sqlCmd.ExecuteNonQuery()
			#$result.Close()
		}
	}
}	

function Update-FBSeasonAverage {
$StoredProcedure = 
@"
CREATE PROCEDURE [dbo].[UpdateSeasonAverages]

AS
	DECLARE @s1 DECIMAL
	DECLARE @s2 DECIMAL
	DECLARE @t1 DECIMAL
	DECLARE @t2 DECIMAL
	DECLARE @c1 DECIMAL

	DECLARE @TempTable Table (RowID int identity, Season nvarchar(100))
	INSERT INTO @TempTable SELECT distinct(Season) from Game
	DECLARE @SeasonCount INT = (SELECT count(season) FROM @TempTable);
	DECLARE @MinCount INT = 1;
	DECLARE @Season nvarchar(100);

	WHILE(@SeasonCount >= @MinCount)
	BEGIN
		SELECT @Season = Season from @TempTable where RowID = @MinCount
		SELECT @s1 = sum(score1) + sum(score2)  FROM Game WHERE Season = @Season
		SELECT @c1 = count(score1) FROM Game WHERE Season = @Season
		SELECT @t1 = SUM(score1) FROM Game WHERE Season = @Season
		SELECT @t2 = SUM(score2) FROM Game WHERE Season = @Season
	
		INSERT SeasonAverage (Season, AverageRunsPerGame, AverageRunsPerTeam)
		SELECT @Season, @s1 / @c1, (@t1 + @t2) / (2 * @c1)
		SET @MinCount = @MinCount + 1
	END

"@
$ConnectionString = "Server=tcp:tcmablsqlsrv.database.windows.net,1433;Database=TCMABL-DEV;User ID=fred@tcmablsqlsrv;Password=Rival420!;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$SQLConnection = New-Object System.Data.SqlClient.SqlConnection
$SQLConnection.ConnectionString = $ConnectionString
$SQLConnection.Open()
$SQLCmd = New-Object System.Data.SqlClient.SqlCommand
$SQLCmd.Connection = $SQLConnection
$SQLCmd.CommandText = $StoredProcedure

$SQLCmd.ExecuteNonQuery()

$SQLCmd.CommandText = "EXEC UpdateSeasonAverages"
$SQLCmd.ExecuteNonQuery()
}