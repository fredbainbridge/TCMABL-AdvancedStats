using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;


namespace TCMABL
{
    
    public class Player
    {
        public string Number;
        public string Name;
        public string Team;
        public string Season;
        public string League;
        public string GameType;
        public int TCMABLID;
        public int GamesPlayed;
        public int PlateAppearances;
        public int AtBats;
        public int Runs;
        public int Hits;
        public int Doubles;
        public int Triples;
        public int HomeRuns;
        public int RunsBattedIn;
        public int HitByPitch;
        public int BaseOnBalls;
        public int StrikeOuts;
        public int SacBunts;
        public int SacFlys;
        public int StolenBases;
        public int CaughtStealing;
        public double Average;
        public double OnBasePercentage;
        public double Slugging;

        public Player() { }
        public Player(string PlayerName, string TeamName) {
            this.Name = PlayerName;
            this.Team = TeamName;
        }
        public Player(string PlayerName, string TeamName, string PlayerNumber)
        {
            this.Name = PlayerName;
            this.Team = TeamName;
            this.Number = PlayerNumber;
        }
    }
}
