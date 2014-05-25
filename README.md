# importSQLView

This script is template for importing data into Hydstra from an external SQL DB View. 
If you want to create your own copy of this script you can replace the text "externaldb" throughout the hyscript file, however you can also simply rename the .hsc and .ini files 

## dbname.config
Configuration of the database occurs in the INI file. It contains

1. Expected views - you can turn views on or off here
2. connection string - this is the critical part of setup for connecting to the external db

## table.view
Views presented by the external db to the Hydstra connection. Syntax is:

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
