﻿$SubscriptionID = "0ce36f9f-68f9-48bd-ab63-e23813e6745a"
$ConnectionString = "Data Source=(localdb)\MSSQLLocalDB;Initial Catalog=master;Integrated Security=True;Connect Timeout=30;Encrypt=False;TrustServerCertificate=False;ApplicationIntent=ReadWrite;MultiSubnetFailover=False"

if(get-module TCMABL)
{
    Remove-Module TCMABL
}
Import-Module .\TCMABL.psm1

Invoke-FBAzureSubscription -SubscriptionID $SubscriptionID

$DBConnection = Get-FBDatabaseReference -ConnectionString $ConnectionString

Remove-FBTables -SQLConnection $DBConnection -Verbose
Create-FBTables -SQLConnection $DBConnection -Verbose