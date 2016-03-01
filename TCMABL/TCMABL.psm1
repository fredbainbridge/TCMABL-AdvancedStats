
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

#Drop Existing Tables
Function Remove-FBTables {
	[CmdletBinding()]
	Param (
		[string[]] $Tables = ("Game","PlayerCareer","SeasonAverage","PlayerCareerAdvancedStat"),	
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
        [AverageRunsPerGame] DECIMAL (18, 4) NOT NULL,
        [AverageRunsPerTeam] DECIMAL (18, 4) NOT NULL,
        [AveragewOBA]        DECIMAL (18, 4) NOT NULL,
        [RunsPerWin]         DECIMAL (18, 4) NOT NULL
    );

"@

$AdvancedStats = 
@"
CREATE TABLE [dbo].[PlayerCareerAdvancedStat] (
    [ID]     INT             IDENTITY (1, 1) NOT NULL,
    [Player] NVARCHAR (MAX)  NULL,
    [Team]   NVARCHAR (MAX)  NULL,
    [Season] NVARCHAR (MAX)  NULL,
    [wOBA]   DECIMAL (18, 2) NOT NULL,
    [wRAA]   DECIMAL (18, 2) NOT NULL,
    [WAR]    DECIMAL (18, 2) NOT NULL
);
"@
    if($SQLConnection.State -ne "Open")
    {
        $SQLConnection.Open()
    }
    $SQLCmd = New-Object System.Data.SqlClient.SqlCommand
    $SQLCmd.Connection = $SQLConnection
    ($Game, $PlayerCareer, $SeasonAverage, $AdvancedStats) | ForEach-Object {
        Write-Verbose "Executing `n $PSITEM"
        $SQLCmd.CommandText = $PSItem
        $null = $sqlCmd.ExecuteNonQuery()
    }
}


#populate tables.
function Update-FBPlayerCareer {
    [CmdletBinding()]
	Param (
		[System.Data.SqlClient.SqlConnection]$SQLConnection,        
        [string]$PlayerCareerDataFile = "https://fredbainbridge.blob.core.windows.net/tcmabl/PlayerCareers.csv" #this is a URL
    )
    
    if($SQLConnection.State -ne "Open")
    {
        $SQLConnection.Open()
    }
    $SQLCmd = New-Object System.Data.SqlClient.SqlCommand
    $SQLCmd.Connection = $SQLConnection
    $StoredProcedureSQL = 
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

    $SQLCmd.CommandText = $StoredProcedureSQL
    $result = $sqlCmd.ExecuteNonQuery()
	
    #get the player data
    $wc = new-object system.net.WebClient
    $webpage = $wc.DownloadData($PlayerCareerDataFile)
    $string = ([System.Text.Encoding]::ASCII.GetString($webpage)).Split("`r`n") | ? {$_}	
    $Player = [TCMABL.Player]::new()  #This object type is loaded at runtime.  See TCMABL.PSD1
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
	    $PlayerName = $Player.Name
        Write-Verbose "Adding $PlayerName"
	    $result = $sqlCmd.ExecuteReader()
	    $result.Close()
    }
}

function Update-FBGames {
	[CmdletBinding()]
	Param (
		[System.Data.SqlClient.SqlConnection]$SQLConnection,        
        [string]$GamesDataFile = "https://fredbainbridge.blob.core.windows.net/tcmabl/Games.csv" #this is a URL
    )
        
	if($SQLConnection.State -ne "Open")
    {
        $SQLConnection.Open()
    }
	$SQLCmd = New-Object System.Data.SqlClient.SqlCommand
	$SQLCmd.Connection = $SQLConnection
	
	$wc = new-object system.net.WebClient
	$webpage = $wc.DownloadData($GamesDataFile)
	$string = ([System.Text.Encoding]::ASCII.GetString($webpage)).Split("`r`n") | ? {$_}	
	Write-Verbose "Adding Games..."
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
		}
	}
    Write-Verbose "Finished"
}	

function Update-FBSeasonAverage {
    [CmdletBinding()]
	Param (
		[System.Data.SqlClient.SqlConnection]$SQLConnection        
    )
        
	if($SQLConnection.State -ne "Open")
    {
        $SQLConnection.Open()
    }
    $StoredProcedure = 
@"
CREATE PROCEDURE [dbo].[UpdateSeasonAverages]

AS
	--variables for average runs
	DECLARE @s1 DECIMAL
	DECLARE @s2 DECIMAL
	DECLARE @t1 DECIMAL
	DECLARE @t2 DECIMAL
	DECLARE @c1 DECIMAL

	--variables for wOBA
	DECLARE @BBCoefficient DECIMAL = .72
	DECLARE @HBPCoefficient DECIMAL = .75
	DECLARE @1BCoefficient DECIMAL = .9
	DECLARE @2BCoefficient DECIMAL = 1.24
	DECLARE @3BCoefficient DECIMAL = 1.56
	DECLARE @HRCoefficient DECIMAL = 1.95
		
	DECLARE @BB INT 
	DECLARE @HBP INT
	DECLARE @HITS INT
	DECLARE @1B INT
	DECLARE @2B INT
	DECLARE @3B INT
	DECLARE @HR INT
	DECLARE @PA INT
	DECLARE @wOBA DECIMAL(18,6)
	DECLARE @RPW DECIMAL(18,6)

	DECLARE @TempTable Table (RowID int identity, Season nvarchar(100))
	INSERT INTO @TempTable SELECT distinct(Season) from Game
	DECLARE @SeasonCount INT = (SELECT count(season) FROM @TempTable);
	DECLARE @MinCount INT = 1;
	DECLARE @Season nvarchar(100);

	DECLARE @twOBA Table (RowID int identity, Season nvarchar(100), wOBA DECIMAL(18,4))
	CREATE Table #twOBAPlayers (RowID int identity, Player nvarchar(max), Season nvarchar(100), wOBA DECIMAL(18,4))

	DECLARE @MinCountPlayer INT = 1;
	DECLARE @PlayerName VARCHAR(MAX);

	WHILE(@SeasonCount >= @MinCount)
	BEGIN
		SELECT @Season = Season from @TempTable where RowID = @MinCount
		SELECT @s1 = sum(score1) + sum(score2)  FROM Game WHERE Season = @Season
		SELECT @c1 = count(score1) FROM Game WHERE Season = @Season
		SELECT @t1 = SUM(score1) FROM Game WHERE Season = @Season
		SELECT @t2 = SUM(score2) FROM Game WHERE Season = @Season
		
		SELECT	@BB = sum(BaseOnBalls), 
				@HBP = sum(HitByPitch),
				@HITS = sum(Hits),
				@2B = sum(Doubles),
				@3B = sum(Triples),
				@HR = sum(HomeRuns),
				@PA = sum(PlateAppearances)
		FROM PlayerCareer WHERE Season = @Season	
		SELECT @1B = @HITS - (@2B + @3B + @HR)
		SET @wOBA = ((@BBCoefficient * @BB)+(@HBPCoefficient*@HBP)+(@1BCoefficient*@1B)+(@2BCoefficient*@2B)+(@3BCoefficient*@3B)+(@HRCoefficient*@HR))/@PA
		SET @RPW = 2 * POWER(@s1 / @c1,.715)

		INSERT SeasonAverage (Season, AverageRunsPerGame, AverageRunsPerTeam, AveragewOBA, RunsPerWin)
		SELECT @Season, @s1 / @c1, (@t1 + @t2) / (2 * @c1), @wOBA, @RPW
		
		SET @MinCount = @MinCount + 1
	END

"@
    $SQLCmd = New-Object System.Data.SqlClient.SqlCommand
    $SQLCmd.Connection = $SQLConnection
    $SQLCmd.CommandText = $StoredProcedure

    $SQLCmd.ExecuteNonQuery()
    Write-Verbose "Calculating Season Averages"
    $SQLCmd.CommandText = "EXEC UpdateSeasonAverages"
    $null = $SQLCmd.ExecuteNonQuery()
    Write-Verbose "Finished"
}

function Update-FBAdvancedStats {
    [CmdletBinding()]
	Param (
		[System.Data.SqlClient.SqlConnection]$SQLConnection        
    )
        
	if($SQLConnection.State -ne "Open")
    {
        $SQLConnection.Open()
    }
    $SQLCmd = New-Object System.Data.SqlClient.SqlCommand
    $SQLCmd.Connection = $SQLConnection
    $StoreProcedure = 
@"
CREATE PROCEDURE [dbo].UpdateAdvancedStats
	
AS
	--wOBA per year
--https://en.wikipedia.org/wiki/WOBA
DECLARE @BBCoefficient DECIMAL = .72
DECLARE @HBPCoefficient DECIMAL = .75
DECLARE @1BCoefficient DECIMAL = .9
DECLARE @2BCoefficient DECIMAL = 1.24
DECLARE @3BCoefficient DECIMAL = 1.56
DECLARE @HRCoefficient DECIMAL = 1.95
		

DECLARE @BB INT 
DECLARE @HBP INT
DECLARE @HITS INT
DECLARE @1B INT
DECLARE @2B INT
DECLARE @3B INT
DECLARE @HR INT
DECLARE @PA INT
DECLARE @wOBA DECIMAL(18,4)
DECLARE @wOBASeason DECIMAL(18,4)
DECLARE @wRAA DECIMAL(18,4)
DECLARE @WAR DECIMAL(18,4)
DECLARE @RPW DECIMAL(18,4)

--DECLARE @twOBA Table (RowID int identity, Season nvarchar(100), wOBA DECIMAL(18,4))
--DECLARE @twOBAPlayers Table (RowID int identity, Player nvarchar(max), Season nvarchar(100), wOBA DECIMAL(18,4))
CREATE Table #twOBAPlayers (RowID int identity, Player nvarchar(max), Team nvarchar(max), Season nvarchar(100), wOBA DECIMAL(18,4), wRAA DECIMAL(18,4), WAR DECIMAL(18,4))

DECLARE @tSeason Table (RowID int identity, Season nvarchar(100))
INSERT INTO @tSeason SELECT distinct(Season) from Game

DECLARE @SEASON VARCHAR(MAX);

DECLARE @SeasonCount INT = (SELECT count(season) FROM @tSeason);
DECLARE @PlayerCount INT
DECLARE @MinCount INT = 1;
DECLARE @MinCountPlayer INT = 1;
DECLARE @PlayerName VARCHAR(MAX);
DECLARE @PlayerTeam VARCHAR(MAX);

WHILE(@SeasonCount >= @MinCount)
	BEGIN
		SELECT @Season = Season from @tSeason where RowID = @MinCount
		SELECT @RPW = RunsPerWin, @wOBASeason = AveragewOBA From SeasonAverage where Season = @SEASON
		
		SET @MinCount = @MinCount + 1
		
		--Individual Players wOBA, wRAA and WAR by season
		INSERT INTO #twOBAPlayers SELECT name, team, season, 0, 0, 0 FROM PlayerCareer WHERE Season = @SEASON and GameType = 'AllGames'
		SELECT @PlayerCount = count(Player) FROM #twOBAPlayers
		SET @MinCountPlayer = 1
		WHILE(@PlayerCount >= @MinCountPlayer)
			BEGIN
				SELECT @PlayerName = Player, @PlayerTeam = team FROM #twOBAPlayers WHERE RowID = @MinCountPlayer
				--SELECT * FROM #twOBAPlayers
				SELECT	@BB = BaseOnBalls, 
						@HBP = HitByPitch,
						@HITS = Hits,
						@2B = Doubles,
						@3B = Triples,
						@HR = HomeRuns,
						@PA = PlateAppearances
				FROM PlayerCareer 
				WHERE Season = @SEASON AND Name = @PlayerName AND GameType = 'AllGames'

				SELECT @1B = @HITS - (@2B + @3B + @HR)
				IF (@PA <> 0 )
				BEGIN
					SET @wOBA = ((@BBCoefficient * @BB)+(@HBPCoefficient*@HBP)+(@1BCoefficient*@1B)+(@2BCoefficient*@2B)+(@3BCoefficient*@3B)+(@HRCoefficient*@HR))/@PA
					SET @wRAA = (@wOBA - @wOBASeason) * @PA
					SET @WAR = @wRAA / @RPW
					
					INSERT INTO PlayerCareerAdvancedStat (Player, Team, Season, wOBA, wRAA, WAR)					
					VALUES (@PlayerName, @PlayerTeam, @SEASON, @wOBA, @wRAA, @WAR)
					--UPDATE #twOBAPlayers SET wOBA = @wOBA, wRAA = @wRAA, WAR = @WAR WHERE RowID = @MinCountPlayer
				END
				SET @MinCountPlayer = @MinCountPlayer + 1	
				
				
			END
		
		DELETE FROM #twOBAPlayers
		DBCC CHECKIDENT('#twOBAPlayers', RESEED, 0)
	--select * from PlayerCareerAdvancedStat where Season = @Season
	END

DROP TABLE #twOBAPlayers
"@
    $SQLCmd.CommandText = $StoreProcedure
    $result = $sqlCmd.ExecuteNonQuery()
    $SQLCmd.CommandTimeout = 0  #this takes a while
    $SQLCmd.CommandText = "EXEC UpdateAdvancedStats"
    Write-Verbose "Updating Advanced Player Stats..."
    $SQLCmd.ExecuteNonQuery()
    Write-Verbose "Done"
}