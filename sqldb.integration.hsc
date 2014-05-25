=setup

[Window]
Head = ARE externaldb SITE - Load SITE fields from externaldb

[Labels]
OUT = END   61 +1 Output File

[Fields]
OUT = 73 +1 INPUT   CHAR       12  0  FALSE   TRUE   0.0 0.0 '#PRINT(P           )'

[Perl]
=cut

package main;
use 5.010;
use strict;
use warnings;
use Spreadsheet::XLSX;
use HySax;
use HyDB;
use HydDLLp;
use JSON;
require 'hydlib.pl';
require 'hydtim.pl';
require 'HydADO.PM';
use Win32::OLE::NLS qw(:LOCALE :TIME);
use hydbsql;
use Hymailer;

##############################################################################
# Globals
##############################################################################
my (%hydtables, $dll);
#my $externaldbHelp = 'externaldbhelp@arrowenergy.com.au';
my $hydstra_admin = 'smaud@arrowenergy.com.au';
my $externaldbHelp = 'smaud@arrowenergy.com.au';
#my $_debug = defined( $ENV{HYDEBUG} );
my $_debug = defined( $ENV{HYDEBUG} );
#Prt('-P',"debug [$_debug]");

##############################################################################
# Subroutines
##############################################################################

sub email_error_message{
  #---------------------------------------------
  # Email externaldb coordinator to notify that there are issues with the view
  #---------------------------------------------
  my (%message, $mail );      
  my ($sql_view,$subject,$msg,$to) = @_;
  $message{'to'}{"$to"}=1; 
  $message{'cc'}{'user:smaud'}=1;
  $message{'subject'}="$subject";
  $message{'text'}="
    
  Dear recipient,

  This is an automatic email alert from the Hydstra system.
  
  $msg
  
  Please address this as a high priority issue.
  
  Kind Regards,
  
  Hydstra system.
  
  ";
  $mail=HyMailer->New(\%message); 
 
}


sub IniHashArray1 {

  #special bongled version to preserve keyword order in an INI file

=Documentation

Function
    Read an INI file into a hash indexed by {section}{keyword}

    Section and keyword are converted by default to lower case, but unlike IniCrack, the blanks inside keywords are not squeezed
    Values are not modified - no case change, no squeeze, only leading and trailing blanks are trimmed
    If you set $leavecase=1 on the call then keywords and sections are left alone, otherwise they are lower-cased (the default).

    If the INI file name does not contain a path then it searches through TEMP then INI and then MISC.
    If the path is explicit then the specified INI file is opened.

Parameters
    $ininame       Name of ini file
    $iniref        Passed by reference hash to contain section_keyword values, e.g. \%ini
    $allowdupes    Optional, if false (0) abort if duplicate keywords encountered, else save last value encountered
    $leavecase     Optional, if true (1), leave the case of sections and keywords alone
    $replacemacros Optional default true - replace macros of the form &hyd-pthname. and &env-envname.

Example
    IniHash('hyconfig.ini',\%ini);

See Also
    IniCrack, Iniexpand, IniMap, IniMapArray, IniListUnmapped, IniListMapped, IniDump, HashDump

Index
    ini
    section
    keyword
    value

=cut

  my ( $ininame, $iniref, $allowdupes, $leavecase, $replacemacros ) = @_;

  $allowdupes    = defined($allowdupes)    ? $allowdupes    : 1;
  $leavecase     = defined($leavecase)     ? $leavecase     : 0;
  $replacemacros = defined($replacemacros) ? $replacemacros : 1;

  my ( $sectkey, $value, $keyword, $openname, $s, %sections );
  my $message = '';
  my $section = '##undef##';

  if ( ref($iniref) ne 'HASH' ) {
    ::Prt( "-RSX", "IniHash should be called using a pass by reference\ne.g. IniHash(\"accounts.ini\",\\\%ini)[", ref($iniref), "]\n" );
  }

  #if the ini file name has an explicit path (it contains a backslash)
  ::Prt( "-RSX", "IniHash called with undefined file name\n" )
        if ( !defined($ininame) );

  if ( $ininame =~ m/\\/ ) {
    $openname = $ininame;    #find the file in the directory specified
  }
  else {
    if ( defined( $ENV{ uc($ininame) } ) && -e $ENV{ uc($ininame) } ) {
      $openname = $ENV{ uc($ininame) };    #find the file in the directory specified by the environment variable
    }
    elsif ( -e ::HyconfigValue('TEMPPATH') . $ininame ) {
      $openname = ::HyconfigValue('TEMPPATH') . $ininame;    #find the file in the TEMP directory
    }
    elsif ( -e ::HyconfigValue('INIPATH') . $ininame ) {
      $openname = ::HyconfigValue('INIPATH') . $ininame;     #find the file in the INI directory
    }
    elsif ( -e ::HyconfigValue('MISCPATH') . $ininame ) {
      $openname = ::HyconfigValue('MISCPATH') . $ininame;    #find the file in the MISC directory
    }
    else {
      $openname = $ininame;                                  #try to find the file in the current directory
    }
  }

  ::OpenFile( *FLDFILE, $openname, "<" );
  while ( $s = <FLDFILE> ) {
    ::Prt( '-T', "INI line [$s]\n" ) if $_debug;

    if ( $s =~ m/^;/ ) {                                     #;comment - do nothing
    }
    elsif ( $s =~ m/^\[(.*?)\]/ ) {                          # [section name]
      $section = ($leavecase) ? $1 : lc($1);
      $message .= "The section [$section] appears more than once in $openname\n"
            if ( $sections{$section}++ );
      ::Prt( '-T', "INI section [$section]\n" ) if $_debug;

    }
    elsif ( $s =~ m/^\s*([a-zA-Z0-9].*?)\s*=(.*)/ ) {        #keyword=value
      $keyword = ($leavecase) ? $1 : lc($1);
      $value = $2;

      #strip leading and trailing spaces off value
      $value =~ s/^ +//;
      $value =~ s/ +$//;
      ::Prt( '-T', "INI keyword [$keyword=$value]\n" ) if $_debug;

      if ( !$allowdupes ) {
        if ( defined( $$iniref{$section}{$keyword} ) ) {
          if ( $keyword !~ m/\$/ ) {                         #ignore keywords with dollars in them, they are crap from Perl in HYSCRIPT jobs
            ::Prt( "-RSX", "*** Duplicate keyword [$section]$keyword in INI file $openname\n" );
          }
        }
      }

      #replace macros in INI file by default, or if keyword is true
      if ( !defined($replacemacros) || $replacemacros ) {
        $value = MacroExpand( $value, $openname );
      }
      push( @{ $$iniref{$section} }, { $keyword => $value } );
    }
  }
  close(FLDFILE);
  Prt( '-T', "\nINI=", HashList( \%$iniref ) );    # if $_debug;
  Prt( "-W", $message ) if $message;

  return;
}


main:{  
  my(%ini,%iniarray);
  my $prog = FileName($0);
  my $repfile=JunkFile('txt');
  my $duplicates = 0;
  my $ids;
  my $script = lc(FileName($0));
  my $inifile = "$script.ini";
  
  IniHash( $inifile, \%ini );
  IniHashArray1($inifile,\%iniarray );
  
  #Open INI File from HYSCRIPT
  IniCrack($ARGV[0],\%ini);
     
  #open report file
  OpenFile(*hREPORT,$ini{"perl_parameters_out"},">");
  
  my %dbi;
  DBILoad(\%dbi);
  #Prt('-R',"DBI:\n".HashDump(\%dbi)."\n");

  my %col_name_setup;
  
  my @views = split (',',$ini{'externaldb.config'}{'views'});
  my $connection = $ini{'externaldb.config'}{'connection'}; 
  Prt('-P',"connection [$connection]");
  
  my %temp_data;
  
  foreach my $view ( @views ){
    my %data;
    my %col_field_mapping;
    my $correct_site_columns = "\nThe correct columns and column order for the [".uc($view)."] view is:\nCOLUMN = ORDER\n---------------\n";
    my $dbi_error = 0;
    my ($msg,$subject);
    
    if ( !defined $ini{$view.'.view'} ){
      email_error_message($view,"Problem with [$prog] INI file","View [".uc($view)."] is defined in the INI file config but is not setup correctly in the [".uc($view).".view] INI file sction, or in the [$prog.hsc] script.",$hydstra_admin);
    }
    else{
      #collect the column name setup from ini
      %col_name_setup = %{$ini{$view.'.view'}};
      
      #Process the fields from INI file so that we can notify email recipient of correct column order
      my @ini_rows = @{$iniarray{$view.'.view'}};
      foreach my $ini_row ( @ini_rows ){
        my %ini_row = %{$ini_row};
        foreach my $ini_col_name ( keys (%ini_row) ){
          my ($ini_col_no,$mapping) = split ('\,',$ini_row{$ini_col_name});
          my $name = $mapping//$ini_col_name;
          #Prt('-P',"ini col [$ini_col_no], mapping [$mapping]");
          #Prt('-P',"name [$name]");
                    
          $correct_site_columns .= uc($ini_col_name)." = $ini_col_no\n";
          $col_field_mapping{$view}{$ini_col_no}=uc($name);#Create a hash of the reverse mappings so that we can create the data hash on the fly
          
          #Verify that the INI table and field exist in dbi definitions
          if ( !defined $dbi{lc($view)} ) {
            $dbi_error =1;
            $msg= "The [".uc($view)."] vicew is defined in the INI file but is not a table according to the dbi setup.";
            $subject = "Problem with [$prog] INI file";
          }
          elsif( !defined $dbi{lc($view)}{'fields'}{lc($name)} ){
            $dbi_error =1;
            $msg = "The [".uc($view)."] view is defined in the INI file config but the [$name] field is not defined correctly according to the dbi setup.";
            $subject = "Problem with [$prog] INI file";
          }
        }
      }
      #Prt('-R',"Data: [".HashDump(\%col_field_mapping)."]\n");
      
      if ( $dbi_error == 1){
        email_error_message($view,$subject,$msg,$hydstra_admin);
        next;
      }
      else{
        #now get the data from externaldb and process it
        my $workspace = "[priv.externaldb$view]";
        
        PrintAndRun('-RS', "\nhydbutil delete $workspace $repfile",0,0); 
        #The externaldb SQL view is called SITE which is a non-standard view naming convention for externaldb, but has been done specifically for Hydstra so that we can consume the view.
        my $uppercase_view = uc($view);
        my $sql_statement = "select * from $uppercase_view";
        #STATION,STNAME,OWNER,STNTYPE,PARENT,LONGITUDE,LATITUDE,ELEVATION,LLDATUM,MAPNAME,POSACC,FIELD,TENEMENTID,BASIN,SITETYPE
        #my $sql_statement = "select STATION,STNAME,OWNER,STNTYPE,PARENT,LONGITUDE,LATITUDE,ELEVATION,LLDATUM,MAPNAME,POSACC from $uppercase_view";
        
        Prt('-S',"\n".NowStr()." Making connection to externaldb\n");
        my $sql=HyDBSQL->new(connect=>$connection,sql=>$sql_statement,report=>'-R',showprogress=>1);                           
        #my $priv_site=HyDB->new("$view","$workspace",{allowdupes => 0, printdest => '-R'}); #do not allowdupes=>0
        
        Prt('-S',"\n".NowStr()." New HyDB instance for $workspace work area\n");
        my $priv_view=HyDB->new(lc($view),$workspace,{allowdupes => 0, printdest => '-R'}); #do not allowdupes=>0
   
        Prt('-S',"\n".NowStr()." Getting [$uppercase_view] SQL view column names and types\n");
        my %sql_col_names;
        my @sql_col_names = $sql->get_col_names;
        my @sql_col_types = $sql->get_col_types;
        ArraytoHash(\@sql_col_names,\%sql_col_names);
        
        Prt('-T',"\n".NowStr()." [$uppercase_view] SQL view col names are: ".join(',',@sql_col_names),"\n");
        
        Prt('-S',"NAME TYPE\n------------\n");
        foreach my $col (0..$#sql_col_names){
          Prt('-S',"name [$sql_col_names[$col]] type [$sql_col_types[$col]]\n");
        }
        Prt('-T',"Col names: \n".HashDump(\@sql_col_names)); 
        Prt('-T',"Col types: \n".HashDump(\@sql_col_types)); 
        
        #Validate that the right columns are present in the view (we validated the INI file setup against the DBI above so INI should be valid)
        my $msg;
        my $incorrect_column_alert = 0;
        Prt('-S',NowStr()." Checking col required from INI for [$uppercase_view] SQL view\n");
        
        Prt('-T',"Colnamesetup\n".HashDump(\%col_name_setup));
        foreach my $column (keys %col_name_setup){
         
          my ($ini_col_no,$mapping) = split('\,',$col_name_setup{$column});
          my $required_column = $mapping//$column;
          Prt('-T',"\required Column [$required_column]\n");
          
          my $uc_required_column = uc($required_column);
          Prt('-S',NowStr()."   [$uc_required_column] col required\n");
          
          if( !defined ( $sql_col_names{uc($column)} ) ){
            Prt('-S',NowStr()."   *** ERROR [$uc_required_column] col required, but not defined in [$uppercase_view] SQL view. Please fix view.\n");
            $msg .= "The column [$uc_required_column] is required. Hydstra cannot update while this problem exists. Please include this column in the externaldb [$view] view.\n";
            $incorrect_column_alert =1;
            next;  
          }
          else{
            Prt('-T',"col name setup".HashDump(\%col_name_setup));
            foreach my $sql_col_no (0..$#sql_col_names){
              my $sql_col_name = $sql_col_names[$sql_col_no];
              
              my ( $ini_col_no, $mapping ) = split('\,',$col_name_setup{lc($sql_col_name)});
              my $req_column = lc($mapping//$sql_col_name);
              Prt('-T',"sql col name [$sql_col_name] sql col no [$ini_col_no] ini col no [$ini_col_no] ini mapping [$mapping], req col [$req_column]\n");

              my ($dbi_col_type,$length,$decimals) = split('\,',$dbi{lc($view)}{'fields'}{lc($req_column)} );
              Prt('-T',"\n - DBI field [$req_column], dbi_col_type,length,decimals [$dbi_col_type,$length,$decimals]");
              
              if ( !defined ( $col_name_setup{lc($sql_col_name)} ) ) {
                $msg .= "Hydstra does not require column [$sql_col_names[$sql_col_no]] to be defined. Hydstra cannot update while this problem exists. Please remove the column from the externaldb [$view] view.\n";
                $incorrect_column_alert =1;
              }
              elsif( $ini_col_no != lc($sql_col_no) ){
                $msg .= "The column [$sql_col_names[$sql_col_no]] is in the wrong order of the externaldb [$view] view.\n   ini col is [$ini_col_no] sql col is [$sql_col_no]\n";
                $incorrect_column_alert =1;
                Prt('-T',"$msg");
              }
              
             if ( $ini{'externaldb.config'}{lc($dbi_col_type)} != $sql_col_types[$sql_col_no] ){
                $msg .= "The column [$sql_col_names[$sql_col_no]] is the wrong type in the externaldb [$view] view. It is [$sql_col_types[$sql_col_no]]. It should be [$ini{'externaldb.config'}{$dbi_col_type}]\n";
                $incorrect_column_alert =1;
               Prt('-X',"$msg");
              }
            }
          }
        }
      
        #Verify that the data from externaldb is provided in the right format according to the dbi definitions.
        Prt('-S',NowStr()." View [$view]. Verifing externaldb data is in dbi formatting\n");
        if ($incorrect_column_alert == 1){
          my $subject = 'externaldb-to-Hydstra Integration Column Error';
          $msg .= $correct_site_columns;
          my $full_message = "There appears to be a problem with externaldb's [$view] SQL view presented to the Hydstra database.\n\n$msg";
          Prt('-S',NowStr()."There appears to be a problem with externaldb's [$view] SQL view presented to the Hydstra database.\n");
          email_error_message($view,$subject,$full_message,$externaldbHelp);
        }
        else{
          my %sites;
          Prt('-S',NowStr()." View [$view]. All good. Getting formatted row\n");
          my $row_num =0;
          my $station_col = $ini{$view.'.view'}{'station'} ;
          my $parent_col  = $ini{$view.'.view'}{'parent'} ;  
          
          my $c1    = $ini{$view.'.view'}{'basin'};      
          my $c2    = $ini{$view.'.view'}{'field'};      
          my $c3    = $ini{$view.'.view'}{'tenementid'}; 
          my $sp2   = $ini{$view.'.view'}{'sitetype'};   
          
          my ($cat1_col,$hyfield)    = split(/\,/,$c1 ) ;  
          my ($cat2_col,$hyfield)    = split(/\,/,$c2 ) ;  
          my ($cat3_col,$hyfield)    = split(/\,/,$c3 ) ;  
          my ($spare2_col,$hyfield)  = split(/\,/,$sp2) ;  
          
          while(1) {
            my %data;
            $row_num++;
            my @d=$sql->get_formatted_row;
            
            last if ($#d==-1);
            #Pickup the STATION field column from INI
            #make sure the station is defined and not equal to nothing
            if ( defined ($d[$station_col]) && ($d[$station_col] ne '' || $d[$station_col] ne ' ' ) ) {
              my $station =  $d[$station_col];
              my $cat1    =  $d[$cat1_col];
              my $cat2    =  $d[$cat2_col];
              my $cat3    =  $d[$cat3_col];
              my $spare2  =  uc($d[$spare2_col]);
              $spare2 =~ s{ }{_}g;
              my $parent  =  uc($d[$parent_col]);
              $parent =~ s{ }{_};
              
              my $posacc = 'N';
              my $type;
              
              #check for dupes
              if ( !defined ( $sites{$station} ) ){            
                foreach my $sql_view_col_no ( 0..$#d ){
                  my $col_no_to_fieldname = $col_field_mapping{$view}{$sql_view_col_no};
                  my ($dbi_col_type,$length,$decimals) = split(',',$dbi{lc($view)}{'fields'}{lc($col_no_to_fieldname)} );
                  $type = $dbi_col_type;  
                  
                  Prt('-T',NowStr()." HashDUmp of mapping for sql view col no[$sql_view_col_no]. ".HashDump(\%{$col_field_mapping{$view}})."                                               \n");
                  Prt('-S',NowStr()." SQL View [$view]. col no to field name [$col_no_to_fieldname]                                               \r");
                  
                  if ( lc ( $col_no_to_fieldname ) eq 'posacc' ){
                    Prt('-T',NowStr()." View [$view]. POSACC special case                                               \r");
                    #POSACC special case
                    $posacc = 'Y';
                    $data{'POSACC'}=( !defined ($d[$sql_view_col_no]) || $d[$sql_view_col_no] eq '') ? 'UNKN' : $d[$sql_view_col_no]; 
                  }
                  elsif ( $decimals > 0 && lc($dbi_col_type) eq 'n'){
                    #Check whether there are any decimals, if so, then sprintf it according to dbi requirements.
                    my $sprintf = '"%'."$length.$decimals".'f"';
                    $data{uc($col_no_to_fieldname)} = ( defined($d[$sql_view_col_no]) ) ? sprintf($sprintf,$d[$sql_view_col_no]) : ''; 
                    #For some reason sprintf seems to be returning a string so we need to get rid of the "
                    $data{uc($col_no_to_fieldname)} =~ s{"}{}g;
                    Prt('-T',NowStr()." View [$view]. Sprintf [$sprintf]. Check decimals  [$data{uc($col_no_to_fieldname)}]                                             \r");
                  }
                  else{
                    Prt('-T',NowStr()." View [$view]. Normal [$d[$sql_view_col_no]]                                               \r");
                    $data{ uc($col_no_to_fieldname) } = $d[$sql_view_col_no]//'';             
                  }
                }
              }
              else{
                Prt('-S',"\n".NowStr()." *** ERROR Duplicate site [$station]\n");
                $ids .= "$d[1]
                ";
                $duplicates = 1;
                next;
              }
              my $site = sprintf("%15s",$station);
              my $par = sprintf("%15s",$parent);
              $data{'LLDATUM'}=~ s{LL_Calc$}{Calc} ; 
              $data{'ORGCODE'}= 'ARE';
              $data{'PARENT'} = $par;
              $data{'CATEGORY5'}= 'AEAQ';
              $data{'CATEGORY1'}= '';
              $data{'SPARE2'}   = $spare2;
              
              $temp_data{CATEGORY2}{$data{'CATEGORY2'}}++;
              $temp_data{CATEGORY3}{$data{'CATEGORY3'}}++;
              $temp_data{CATEGORY1}{$data{'CATEGORY1'}}++;
              $temp_data{SPARE2}{$data{'SPARE2'}}++;
              
              $data{'CATEGORY3'}= '';
             
              Prt('-S',NowStr()." View [$view]. Type ok [$type]. POSACC [$posacc]. Site [$site]. Row [$row_num].                   \r");
              
              $priv_view->sethash(\%data);
              $priv_view->write;
              $priv_view->clear;
              Prt('-S',NowStr()." $prog HYDB->write [$data{'STATION'}] to $workspace               \r");
              undef %data;
              $sites{$station}++;              
            }
            else{
              Prt('-SR',"\n".NowStr()." externaldb SQL View [$view] has a problem with the station column [$station_col]. Station is either undefined or blank. Please fix the view.                     \r");
            }
          }
          $priv_view->close();
          $priv_view->write;
          $priv_view->clear;
          Prt('-T',"Data Hash:\n[".HashDump(\%data)."]");    
        }
        if ( $duplicates == 1 ){
          my $subject = 'externaldb-to-Hydstra Integration Duplicate Alert';
          my $msg = "There is at least one duplicate well ID in the externaldb database. The Hydstra database has not imported the duplicate(s) with the following HOLEID(s):
        
        $ids";
          my $full_message = "There appears to be a problem with externaldb's [$view] SQL view presented to the Hydstra database.\n$msg";
          email_error_message($view,$subject,$msg,$externaldbHelp);
        }
        Prt('-S',"\n".NowStr()." Updating Archive from $workspace\n");
        
        PrintAndRun('-S', qq{hydbutil update site $workspace "STATION,STNAME,OWNER,STNTYPE,LONGITUDE,LATITUDE,ELEV,LLDATUM,MAPNAME,POSACC,CATEGORY5,CATEGORY2,CATEGORY3,CATEGORY1,SPARE2" YES YES $repfile},0,0);   
        $correct_site_columns = '';
      }  
    }
    undef %data;
  }
  #Prt('-L',"Hash Dump [".HashDump(\%temp_data)."]\n");
  close(hREPORT);
}
