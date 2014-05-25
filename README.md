# importSQLView

This script is template for importing data into Hydstra from an external SQL DB View. 
If you want to create your own copy of this script you can replace the text "externaldb" throughout the hyscript file, however you can also simply rename the .hsc and .ini files 


# INI file setup
Configuration of the database occurs in the INI file. It contains the two sections below.

## Section [dbname.config]
This section enables you to setup the link and views in the external db.

1. Expected views - you can turn views on or off here
2. connection string - this is the critical part of setup for connecting to the external db and is a black box

The following template acts as something of a guide. You will need to add your own details in the variables between %...%

```
connection = Provider=%some_SQL_provider_ID%;Persist Security Info=False;Integrated Security=SSPI;Database=%some_db%;Server=%servername\\dbname%;Trusted Connection=True
```

## Section [table.view]
This section enables you to setup different views presented by the external db to the Hydstra connection. 
You set up the fields and their order expected in the external db, acting as a type of validation. 
You can also map the external field to a hydstra field in this view. Syntax is:

* field=order,field mapping

E.g. 
```
station=0
stname=1
owner=2
stntype=3
parent=4
longitude=5
latitude=6
elevation=7,elev

```
