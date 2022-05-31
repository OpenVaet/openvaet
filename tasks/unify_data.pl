#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path);
use JSON;
use FindBin;
use lib "$FindBin::Bin/../lib";

# Project's libraries.
use global;
use config;
use time;

# Sources to be updated.
my $ecdcSourceId          = 1;
my $cdcSourceId           = 2;

# Initiating arrays which will contain the merged reports.
my %reports               = ();
my %eventsAdded           = ();

# Initiating ECDC cache data.
my %ecdcDrugs             = ();
my %ecdcDrugsNotices      = ();
my %ecdcReactions         = ();
my %ecdcReactionsOutcomes = ();
my %ecdcNoticeReactions   = ();
my %cdcSymptoms           = ();
my %cdcVaccines           = ();

my %unknownSubstances = ();

# Fetching ECDC drugs.
say "fetching drugs ...";
ecdc_drugs();

# Fetching ECDC drugs <-> notices relations.
say "fetching drugs notices ...";
ecdc_drug_notices();

# Fetching ECDC reactions.
say "fetching reactions ...";
ecdc_reactions();

# Fetching ECDC reactions outcomes.
say "fetching drugs outcomes ...";
ecdc_reaction_outcomes();

# Fetching ECDC notices <-> reactions relations.
say "fetching notices reactions ...";
ecdc_notice_reactions();

# Fetching ECDC notices.
say "fetching notices ...";
ecdc_notices();

# Fetching CDC's data
say "fetching symptoms ...";
cdc_symptoms();
say "fetching vaccines ...";
cdc_vaccines();
say "fetching reports ...";
cdc_reports();

# Priting end usage JSON files.
print_reports();

if (keys %unknownSubstances) {
	say "Alert ; some substances aren't categorized.";
	open my $out, '>:utf8', 'unknown_substances.txt';
	for my $substanceName (sort keys %unknownSubstances) {
		print $out "$substanceName\n";
	}
	close $out;
	p%unknownSubstances;
	die;
}


# p%stats;

sub ecdc_drugs {
	my $dTb = $dbh->selectall_hashref("SELECT id as ecdcDrugId, name as ecdcDrugName FROM ecdc_drug", 'ecdcDrugId');
	for my $ecdcDrugId (sort{$a <=> $b} keys %$dTb) {
	    my $ecdcDrugName = %$dTb{$ecdcDrugId}->{'ecdcDrugName'} // die;
	    die "illegal char" if $ecdcDrugName =~ /;/;
	    $ecdcDrugs{$ecdcDrugId}->{'ecdcDrugName'} = $ecdcDrugName;
	}
}

sub ecdc_drug_notices {
	my $dNTb = $dbh->selectall_hashref("SELECT id as ecdcDrugNoticeId, ecdcDrugId, ecdcNoticeId FROM ecdc_drug_notice", 'ecdcDrugNoticeId');
	for my $ecdcDrugNoticeId (keys %$dNTb) {
	    my $ecdcDrugId   = %$dNTb{$ecdcDrugNoticeId}->{'ecdcDrugId'}   // die;
	    my $ecdcNoticeId = %$dNTb{$ecdcDrugNoticeId}->{'ecdcNoticeId'} // die;
	    $ecdcDrugsNotices{$ecdcNoticeId}->{$ecdcDrugId} = 1;
	}
}

sub ecdc_reactions {
	my $rTb = $dbh->selectall_hashref("SELECT id as ecdcReactionId, name as ecdcReactionName FROM ecdc_reaction", 'ecdcReactionId');
	%ecdcReactions = %$rTb;
}

sub ecdc_reaction_outcomes {
	my $rOTb = $dbh->selectall_hashref("SELECT id as ecdcReactionOutcomeId, name as ecdcReactionOutcomeName FROM ecdc_reaction_outcome", 'ecdcReactionOutcomeId');
	%ecdcReactionsOutcomes = %$rOTb;
}

sub ecdc_notice_reactions {
	my $nRtb = $dbh->selectall_hashref("SELECT id as ecdcNoticeReactionId, ecdcNoticeId, ecdcReactionId, ecdcReactionOutcomeId FROM ecdc_notice_reaction", 'ecdcNoticeReactionId');
	for my $ecdcNoticeReactionId (sort{$a <=> $b} keys %$nRtb) {
	    my $ecdcNoticeId          = %$nRtb{$ecdcNoticeReactionId}->{'ecdcNoticeId'}          // die;
	    my $ecdcReactionId        = %$nRtb{$ecdcNoticeReactionId}->{'ecdcReactionId'}        // die;
	    my $ecdcReactionOutcomeId = %$nRtb{$ecdcNoticeReactionId}->{'ecdcReactionOutcomeId'} // die;
	    $ecdcNoticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcNoticeReactionId'} = $ecdcNoticeReactionId;
	    $ecdcNoticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcReactionOutcomeId'} = $ecdcReactionOutcomeId;
	}
}

sub ecdc_notices {
	my $sql               = "
	    SELECT
	        ecdc_notice.id as ecdcNoticeId,
	        internalId as reference,
	        ICSRUrl as url,
	        receiptTimestamp,
	        ecdcSexId,
	        ecdc_sex.name as ecdcSexName,
	        pdfPath,
	        ecdcSeriousness,
	        ecdcReporterType,
	        formSeriousness,
	        formReporterType,
	        ecdcGeographicalOrigin,
	        ecdcYearId,
	        ecdcAgeGroup,
	        ecdc_year.name as ecdcYearName,
	        hasDied,
	        isSerious
	    FROM ecdc_notice
	        LEFT JOIN ecdc_year ON ecdc_year.id = ecdc_notice.ecdcYearId
	        LEFT JOIN ecdc_sex  ON ecdc_sex.id  = ecdc_notice.ecdcSexId";
	my $tb               = $dbh->selectall_hashref($sql, 'ecdcNoticeId');
	my $totalEcdcNotices = 0;
	my $currentDatetime  = time::current_datetime();
	my ($currentDay)     = split ' ', $currentDatetime;
	for my $ecdcNoticeId (sort{$a <=> $b} keys %$tb) {
	    next unless keys %{$ecdcDrugsNotices{$ecdcNoticeId}}; # Happens when we are indexing reports live in parallel only.
	    $totalEcdcNotices++;
	    my $reference                    = %$tb{$ecdcNoticeId}->{'reference'}                          // die;
	    my $url                          = %$tb{$ecdcNoticeId}->{'url'}                                // die;
	    my $ecdcSeriousness              = %$tb{$ecdcNoticeId}->{'ecdcSeriousness'}                    // die;
	    my $ecdcSeriousnessName          = $enums{'ecdcSeriousness'}->{$ecdcSeriousness}               // die;
	    my $ecdcReporterType             = %$tb{$ecdcNoticeId}->{'ecdcReporterType'}                   // die;
	    my $ecdcReporterTypeName         = $enums{'ecdcReporterType'}->{$ecdcReporterType}             // die;
	    if ($ecdcReporterTypeName eq 'Not Specified') {
	    	$ecdcReporterTypeName = 'Non Healthcare Professional';
	    	$ecdcReporterType = 2;
	    }
	    my $ecdcGeographicalOrigin       = %$tb{$ecdcNoticeId}->{'ecdcGeographicalOrigin'}             // die;
	    my $ecdcGeographicalOriginName   = $enums{'ecdcGeographicalOrigin'}->{$ecdcGeographicalOrigin} // die;
	    my $ecdcYearId                   = %$tb{$ecdcNoticeId}->{'ecdcYearId'}                         // die;
	    my $ecdcAgeGroup                 = %$tb{$ecdcNoticeId}->{'ecdcAgeGroup'}                       // die;
	    my $ecdcAgeGroupName             = $enums{'ecdcAgeGroup'}->{$ecdcAgeGroup}                     // die;
	    my $ecdcYearName                 = %$tb{$ecdcNoticeId}->{'ecdcYearName'}                       // die;
	    my $ecdcSexId                    = %$tb{$ecdcNoticeId}->{'ecdcSexId'}                          // die;
	    my $ecdcSexName                  = %$tb{$ecdcNoticeId}->{'ecdcSexName'}                        // die;
	    my $receiptTimestamp             = %$tb{$ecdcNoticeId}->{'receiptTimestamp'}                   // die;
	    my $hasDied                      = %$tb{$ecdcNoticeId}->{'hasDied'}                            // die;
		$hasDied                         = unpack("N", pack("B32", substr("0" x 32 . $hasDied, -32)));
	    my $isSerious                    = %$tb{$ecdcNoticeId}->{'isSerious'}                          // die;
		$isSerious                       = unpack("N", pack("B32", substr("0" x 32 . $isSerious, -32)));
	    my $receiptDatetime              = time::timestamp_to_datetime($receiptTimestamp);
	    my ($receiptDate)                = split ' ', $receiptDatetime;
	    die if exists $eventsAdded{'parsed'}->{$reference};
	    $eventsAdded{'parsed'}->{$reference} = 1;
	    my %obj  = ();
	    $obj{'reference'}                = $reference;
	    $obj{'yearName'}                 = $ecdcYearName;
	    $obj{'receiptDate'}              = $receiptDate;
	    $obj{'sex'}                      = $ecdcSexId;
	    $obj{'sexName'}                  = $ecdcSexName;
	    $obj{'ageGroup'}                 = $ecdcAgeGroup;
	    $obj{'ageGroupName'}             = $ecdcAgeGroupName;
	    $obj{'seriousnessName'}          = $ecdcSeriousnessName;
	    $obj{'reporterType'}             = $ecdcReporterType;
	    $obj{'reporterTypeName'}         = $ecdcReporterTypeName;
        $obj{'sourceId'}                 = 1;
	    $obj{'source'}                   = "EudraVigilance - $ecdcGeographicalOriginName";
	    $obj{'url'}                      = $url;
	    $obj{'age'}                      = undef;
	    $obj{'description'}              = undef;
        $obj{'lifeThreatning'}           = undef;
        $obj{'hospitalized'}             = undef;
        $obj{'permanentDisability'}      = undef;

	    # Incrementing related substances.
	    my $drugs;
	    my ($isCovid, $isOtherVaccine, $isOtherVaccinePlusCovid) = (0, 0, 0);
	    die unless $ecdcDrugsNotices{$ecdcNoticeId};
	    for my $ecdcDrugId (sort{$a <=> $b} keys %{$ecdcDrugsNotices{$ecdcNoticeId}}) {
	        my $ecdcDrugName = $ecdcDrugs{$ecdcDrugId}->{'ecdcDrugName'} // die;
        	my ($substanceCategory, $substanceShortenedName) = substance_synthesis("ECDC - $ecdcDrugName");
            if ($substanceCategory eq 'COVID-19') {
            	$isCovid = 1;
            } else {
            	if ($substanceCategory) {
            		$isOtherVaccine = 1;
            	}
            }
	        my %dObj = ();
	        $dObj{'substanceName'}      = $ecdcDrugName;
            $dObj{'substanceShortName'} = $substanceShortenedName;
            $dObj{'substanceCategory'}  = $substanceCategory;
	        push @{$obj{'substances'}}, \%dObj;
	    }
	    if ($isOtherVaccine && $isCovid) {
	    	$isOtherVaccinePlusCovid = 1;
	    }
	    next unless $isOtherVaccine || $isCovid;

	    # Incrementing related reactions.
	    my $hasDiedFromReaction = 0;
	    for my $ecdcReactionId (sort{$a <=> $b} keys %{$ecdcNoticeReactions{$ecdcNoticeId}}) {
	        my $ecdcReactionOutcomeId = $ecdcNoticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcReactionOutcomeId'} // die;
	        my $ecdcReactionName = $ecdcReactions{$ecdcReactionId}->{'ecdcReactionName'} // die;
	        my $ecdcReactionOutcomeName = $ecdcReactionsOutcomes{$ecdcReactionOutcomeId}->{'ecdcReactionOutcomeName'} // die;
	        # say "ecdcReactionId          : $ecdcReactionId";
	        # say "ecdcReactionName        : $ecdcReactionName";
	        # say "ecdcReactionOutcomeId   : $ecdcReactionOutcomeId";
	        # say "ecdcReactionOutcomeName : $ecdcReactionOutcomeName";
	        $hasDiedFromReaction = 1 if $ecdcReactionOutcomeName eq 'Fatal';
	        my %rObj    = ();
	        $rObj{'reactionName'}        = $ecdcReactionName;
	        $rObj{'reactionOutcomeName'} = $ecdcReactionOutcomeName;
	        push @{$obj{'reactions'}}, \%rObj;
	    }

	    # Setting tags.
	    if ($hasDiedFromReaction == 1) {
	    	unless ($hasDied) {
	    		$hasDied = 1;
	    		my $sth = $dbh->prepare("UPDATE ecdc_notice SET hasDied = 1, isSerious = 1 WHERE id = $ecdcNoticeId");
	    		$sth->execute() or die $sth->err();
	    	}
	    } elsif ($ecdcSeriousnessName eq 'Serious') {
	    	unless ($isSerious) {
	    		$isSerious = 1;
	    		my $sth = $dbh->prepare("UPDATE ecdc_notice SET isSerious = 1 WHERE id = $ecdcNoticeId");
	    		$sth->execute() or die $sth->err();
	    	}
	    }

	    # Incrementing data.
	    $obj{'isOtherVaccine'}               = $isOtherVaccine;
	    $obj{'isCovid'}                      = $isCovid;
	    $obj{'isOtherVaccinePlusCovid'}      = $isOtherVaccinePlusCovid;

	    # Defining stat section.
	    my $statSection;
	    if ($isOtherVaccinePlusCovid) {
	    	$statSection = 'COVID19+OTHER';
	    } else {
	    	if ($isCovid) {
	    		$statSection = 'COVID19';
    		} else {
	    		$statSection = 'OTHER';
    		}
	    }
    	$obj{'patientDied'}                  = $hasDied;
    	$obj{'isSerious'}                    = $isSerious;
    	$obj{'statSection'}                  = $statSection;
    	my $intDate = $receiptDate;
    	$intDate =~ s/\D//g;
    	push @{$reports{$intDate}}, \%obj;
	}

	if ($totalEcdcNotices) {
		my $sth = $dbh->prepare("UPDATE source SET totalReports = $totalEcdcNotices WHERE id = $ecdcSourceId");
		$sth->execute() or die $sth->err();
	}
}

sub cdc_symptoms {
    # Fetching symptoms.
    my $cSTb = $dbh->selectall_hashref("SELECT id as cdcSymptomId, name as cdcSymptomName FROM cdc_symptom", 'cdcSymptomId');
    for my $cdcSymptomId (sort{$a <=> $b} keys %$cSTb) {
        my $cdcSymptomName = %$cSTb{$cdcSymptomId}->{'cdcSymptomName'} // die;
        $cdcSymptoms{$cdcSymptomId}->{'cdcSymptomName'} = $cdcSymptomName;
    }
}

sub cdc_vaccines {
    # Fetching vaccines.
    my $cVTb = $dbh->selectall_hashref("
        SELECT
            cdc_vaccine.id as cdcVaccineId,
            cdc_vaccine.cdcVaccineTypeId,
            cdc_vaccine_type.name as cdcVaccineTypeName,
            cdc_vaccine.cdcManufacturerId,
            cdc_vaccine.cdcVaccineTypeId,
            cdc_manufacturer.name as cdcManufacturerName,
            cdc_vaccine.name as cdcVaccineName
        FROM cdc_vaccine
            LEFT JOIN cdc_manufacturer ON cdc_manufacturer.id = cdc_vaccine.cdcManufacturerId
            LEFT JOIN cdc_vaccine_type ON cdc_vaccine_type.id = cdc_vaccine.cdcVaccineTypeId
        ", 'cdcVaccineId');
    for my $cdcVaccineId (sort{$a <=> $b} keys %$cVTb) {
        my $cdcManufacturerId   = %$cVTb{$cdcVaccineId}->{'cdcManufacturerId'}   // die;
        my $cdcManufacturerName = %$cVTb{$cdcVaccineId}->{'cdcManufacturerName'} // die;
        my $cdcVaccineTypeId    = %$cVTb{$cdcVaccineId}->{'cdcVaccineTypeId'}    // die;
        my $cdcVaccineTypeName  = %$cVTb{$cdcVaccineId}->{'cdcVaccineTypeName'}  // die;
        my $cdcVaccineName      = %$cVTb{$cdcVaccineId}->{'cdcVaccineName'}      // die;
        $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerId'}   = $cdcManufacturerId;
        $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerName'} = $cdcManufacturerName;
        $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeId'}    = $cdcVaccineTypeId;
        $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeName'}  = $cdcVaccineTypeName;
        $cdcVaccines{$cdcVaccineId}->{'cdcVaccineName'}      = $cdcVaccineName;
    }
}

sub cdc_reports {
    # Fetching notices.
    my @cdcReports             = ();
    my $sql                    = "
        SELECT
            cdc_report.id as cdcReportId,
            cdcStateId,
            cdc_state.name as cdcStateName,
            cdc_report.internalId,
            vaccinationDate,
            cdcReceptionDate,
            cdcSexeId as cdcSex,
            cdc_sexe.name as cdcSexName,
            cdcVaccineAdministrator,
            patientAge,
            aEDescription,
            patientDied,
            lifeThreatning,
            hospitalized,
            permanentDisability,
            parsingTimestamp
        FROM cdc_report
            LEFT JOIN cdc_state ON cdc_state.id = cdc_report.cdcStateId
            LEFT JOIN cdc_sexe ON cdc_sexe.id = cdc_report.cdcSexeId";
    my $tb        = $dbh->selectall_hashref($sql, 'cdcReportId');
    for my $cdcReportId (sort{$a <=> $b} keys %$tb) {
        my $cdcStateId                   = %$tb{$cdcReportId}->{'cdcStateId'}              // die;
        my $cdcStateName                 = %$tb{$cdcReportId}->{'cdcStateName'}            // die;
        my $reference                    = %$tb{$cdcReportId}->{'internalId'}              // die;
        my $aEDescription                = %$tb{$cdcReportId}->{'aEDescription'};
        my $vaccinationDate              = %$tb{$cdcReportId}->{'vaccinationDate'};
        my $receiptDate                  = %$tb{$cdcReportId}->{'cdcReceptionDate'};
        my $cdcSex                       = %$tb{$cdcReportId}->{'cdcSex'}                  // die;
        my $cdcSexName                   = %$tb{$cdcReportId}->{'cdcSexName'}              // die;
        my $patientAge                   = %$tb{$cdcReportId}->{'patientAge'};
        my $patientDied                  = %$tb{$cdcReportId}->{'patientDied'}             // die;
        my $lifeThreatning               = %$tb{$cdcReportId}->{'lifeThreatning'}          // die;
        my $hospitalized                 = %$tb{$cdcReportId}->{'hospitalized'}            // die;
        my $permanentDisability          = %$tb{$cdcReportId}->{'permanentDisability'}     // die;
        my $cdcVaccineAdministrator      = %$tb{$cdcReportId}->{'cdcVaccineAdministrator'} // die;
        my $cdcVaccineAdministratorName  = $enums{'cdcVaccineAdministrator'}->{$cdcVaccineAdministrator} // die;
        $patientDied                     = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
        $lifeThreatning                  = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
        $hospitalized                    = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
        $permanentDisability             = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
	    next if exists $eventsAdded{'parsed'}->{$reference};
	    $eventsAdded{'parsed'}->{$reference} = 1;
	    die unless $patientDied         == 0 || $patientDied         == 1;
	    die unless $lifeThreatning      == 0 || $lifeThreatning      == 1;
	    die unless $hospitalized        == 0 || $hospitalized        == 1;
	    die unless $permanentDisability == 0 || $permanentDisability == 1;
        my ($ageGroup, $ageGroupName) = age_group_from_age($patientAge);

        # Integrating vaccines details.
        my $cRVTb = $dbh->selectall_hashref("SELECT cdcVaccineId, dose FROM cdc_report_vaccine WHERE cdcReportId = $cdcReportId", 'cdcVaccineId') or die $!;
        next unless keys %$cRVTb;
        my ($isCovid, $isOtherVaccine, $isOtherVaccinePlusCovid) = (0, 0, 0);
        my %obj = ();
        for my $cdcVaccineId (sort{$a <=> $b} keys %$cRVTb) {
            my $cdcVaccineName      = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineName'}      // die;
            my $cdcManufacturerId   = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerId'}   // die;
            my $cdcManufacturerName = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerName'} // die;
            my $cdcVaccineTypeId    = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeId'}    // die;
            my $cdcVaccineTypeName  = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeName'}  // die;
            my $dose                = %$cRVTb{$cdcVaccineId}->{'dose'}                     // '';
            my $drugName = "$cdcManufacturerName - $cdcVaccineTypeName - $cdcVaccineName";
        	my ($substanceCategory, $substanceShortenedName) = substance_synthesis("CDC - $drugName");
            # say "cdcVaccineTypeName : $cdcVaccineTypeName";
            if ($substanceCategory eq 'COVID-19') {
            	$isCovid = 1;
            } else {
            	if ($substanceCategory) {
            		$isOtherVaccine = 1;
            	}
            }
            my %o                    = ();
            $o{'substanceName'}      = $drugName;
            $o{'substanceShortName'} = $substanceShortenedName;
            $o{'substanceCategory'}  = $substanceCategory;
            push @{$obj{'substances'}}, \%o;
        }
        next unless $isCovid || $isOtherVaccine;
        if ($isCovid && $isOtherVaccine) {
        	$isOtherVaccinePlusCovid = 1;
        }

        # Integrating symptoms related to the report.
        my $cRSTb = $dbh->selectall_hashref("SELECT cdcSymptomId FROM cdc_report_symptom WHERE cdcReportId = $cdcReportId", 'cdcSymptomId') or die $!;
        for my $cdcSymptomId (sort{$a <=> $b} keys %$cRSTb) {
            my $cdcSymptomName = $cdcSymptoms{$cdcSymptomId}->{'cdcSymptomName'} // die;
            my %o = ();
            $o{'reactionOutcomeName'} = undef;
            $o{'reactionName'}        = $cdcSymptomName;
            push @{$obj{'reactions'}}, \%o;
        }
        my ($reporterTypeName, $reporterType) = reporter_type_from_reporter($cdcVaccineAdministratorName);
        my $seriousnessName                   = seriousness_from_characteristics($hospitalized, $lifeThreatning, $patientDied, $permanentDisability);
        my ($sex, $sexName)                   = sex_from_cdc_sex($cdcSexName);
        my $source                            = "CDC - $cdcStateName";
        my ($yearName)                        = split '-', $receiptDate;

        # say "cdcVaccineAdministratorName : $cdcVaccineAdministratorName";
        $obj{'reporterTypeName'}         = $reporterTypeName;
        $obj{'reporterType'}             = $reporterType;
        $obj{'isCovid'}                  = $isCovid;
        $obj{'yearName'}                 = $yearName;
        $obj{'isOtherVaccine'}           = $isOtherVaccine;
        $obj{'isOtherVaccinePlusCovid'}  = $isOtherVaccinePlusCovid;
        $obj{'url'}                      = undef;
        $obj{'description'}              = $aEDescription;
        $obj{'sourceId'}                 = 2;
        $obj{'source'}                   = $source;
        $obj{'seriousnessName'}          = $seriousnessName;
        $obj{'reference'}                = "$reference-1";
        $obj{'vaccinationDate'}          = $vaccinationDate;
        $obj{'receiptDate'}              = $receiptDate;
        $obj{'ageGroup'}                 = $ageGroup;
        $obj{'ageGroupName'}             = $ageGroupName;
        $obj{'sex'}                      = $sex;
        $obj{'sexName'}                  = $sexName;
        $obj{'patientAge'}               = $patientAge;
        $obj{'patientDied'}              = $patientDied;
        $obj{'lifeThreatning'}           = $lifeThreatning;
        $obj{'hospitalized'}             = $hospitalized;
        $obj{'permanentDisability'}      = $permanentDisability;

	    # Defining stat section.
	    my $statSection;
	    if ($isOtherVaccinePlusCovid) {
	    	$statSection = 'COVID19+OTHER';
	    } else {
	    	if ($isCovid) {
	    		$statSection = 'COVID19';
    		} else {
	    		$statSection = 'OTHER';
    		}
	    }
	    my $isSerious = 0;
	    if ($seriousnessName eq 'Serious') {
	    	$isSerious = 1;
	    }
    	$obj{'isSerious'}                    = $isSerious;
    	$obj{'statSection'}                  = $statSection;
    	my $intDate = $receiptDate;
    	$intDate =~ s/\D//g;
    	push @{$reports{$intDate}}, \%obj;
    }
    my $totalCdcReports = keys %$tb;
	if ($totalCdcReports) {
		my $sth = $dbh->prepare("UPDATE source SET totalReports = $totalCdcReports WHERE id = $cdcSourceId");
		$sth->execute() or die $sth->err();
	}
}

sub age_group_from_age {
	my ($patientAge) = @_;
	my ($ageGroup, $ageGroupName);
	if (!$patientAge) {
		$ageGroupName = 'Not Specified';
		$ageGroup     = 8;
	} elsif ($patientAge >= 0 && $patientAge <= 0.165) {
		$ageGroupName = '0-1 Month';
		$ageGroup     = 1;
	} elsif ($patientAge > 0.165 && $patientAge <= 2.99) {
		$ageGroupName = '2 Months - 2 Years';
		$ageGroup     = 2;
	} elsif ($patientAge > 2.99 && $patientAge <= 11.99) {
		$ageGroupName = '3-11 Years';
		$ageGroup     = 3;
	} elsif ($patientAge > 11.99 && $patientAge <= 17.99) {
		$ageGroupName = '12-17 Years';
		$ageGroup     = 4;
	} elsif ($patientAge > 17.99 && $patientAge <= 64.99) {
		$ageGroupName = '18-64 Years';
		$ageGroup     = 5;
	} elsif ($patientAge > 64.99 && $patientAge <= 85.99) {
		$ageGroupName = '65-85 Years';
		$ageGroup     = 6;
	} elsif ($patientAge > 85.99) {
		$ageGroupName = 'More than 85 Years';
		$ageGroup     = 7;
	} else {
		die "patientAge : $patientAge";
	}
	return ($ageGroup, $ageGroupName);
}

sub reporter_type_from_reporter {
	my ($cdcVaccineAdministratorName) = @_;
	my ($reporterTypeName, $reporterType);
	if (
		$cdcVaccineAdministratorName eq 'Unknown' ||
		$cdcVaccineAdministratorName eq 'Private' ||
		$cdcVaccineAdministratorName eq 'Public'  ||
		$cdcVaccineAdministratorName eq 'Other'   ||
		$cdcVaccineAdministratorName eq 'Work'
	) {
		$reporterType = '1';
		$reporterTypeName = 'Non Healthcare Professional';
	} elsif (
		$cdcVaccineAdministratorName eq 'Military' ||
		$cdcVaccineAdministratorName eq 'Pharmacy' ||
		$cdcVaccineAdministratorName eq 'School'   ||
		$cdcVaccineAdministratorName eq 'Senior Living'
	) {
		$reporterType = '2';
		$reporterTypeName = 'Healthcare Professional';
	} else {
		die "cdcVaccineAdministratorName : $cdcVaccineAdministratorName";
	}
	return ($reporterTypeName, $reporterType);
}

sub seriousness_from_characteristics {
	my ($hospitalized, $lifeThreatning, $patientDied, $permanentDisability) = @_;
	# say "$hospitalized, $lifeThreatning, $patientDied, $permanentDisability";
	# die;
	my $seriousnessName;
	if ($patientDied eq 1 || $lifeThreatning eq 1 || $hospitalized eq 1 || $permanentDisability eq 1) {
		$seriousnessName = 'Serious';
	} else {
		$seriousnessName = 'Non-Serious';
	}
	return $seriousnessName;
}

sub sex_from_cdc_sex {
	my ($cdcSexName) = @_;
	my ($sex, $sexName);
	if ($cdcSexName eq 'Female') {
		$sex = 1;
		$sexName = 'Female';
	} elsif ($cdcSexName eq 'Male') {
		$sex = 2;
		$sexName = 'Male';
	} elsif ($cdcSexName eq 'Unknown') {
		$sex = 3;
		$sexName = 'Unknown';
	} else {
		die "cdcSexName : $cdcSexName";
	}
	return ($sex, $sexName);
}

sub substance_synthesis {
    my ($substanceName) = @_;
    return 0 if
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (FLULAVAL QUADRIVALENT)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - RV1 - ROTAVIRUS (ROTARIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - MENB - MENINGOCOCCAL B (BEXSERO)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HIBV - HIB (PEDVAXHIB)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - MNQ - MENINGOCOCCAL CONJUGATE (MENVEO)' ||
        $substanceName eq 'CDC - BERNA BIOTECH, LTD - TYP - TYPHOID LIVE ORAL TY21A (VIVOTIF)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HIBV - HIB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - FLU3 - INFLUENZA (SEASONAL) (FLUZONE)' ||
        $substanceName eq 'CDC - AVENTIS PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - MENHIB - MENINGOCOCCAL CONJUGATE + HIB (MENITORIX)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLUA3 - INFLUENZA (SEASONAL) (FLUAD)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - RVX - ROTAVIRUS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - RV5 - ROTAVIRUS (ROTATEQ)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HPV2 - HPV (CERVARIX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - MMR - MEASLES + MUMPS + RUBELLA (PRIORIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - VARCEL - VARICELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE HIGH-DOSE QUADRIVALENT)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - PPV - PNEUMO (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - PNC10 - PNEUMO (SYNFLORIX)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - VARCEL - VARICELLA (VARIVAX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (GSK))' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HEPA - HEP A (VAQTA)' ||
        $substanceName eq 'CDC - MASS. PUB HLTH BIOL LAB - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HEPATYP - HEP A + TYP (HEPATYRIX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE HIGH-DOSE)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - PPV - PNEUMO (PNEUMOVAX)' ||
        $substanceName eq 'CDC - MEDEVA PHARMA, LTD. - FLU3 - INFLUENZA (SEASONAL) (FLUVIRIN)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - BCG - BCG (MYCOBAX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - LYME - LYME (LYMERIX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (TIV DRESDEN)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (FLULAVAL)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (QIV QUEBEC)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (QIV DRESDEN)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (FLUARIX)' ||
        $substanceName eq 'CDC - PROTEIN SCIENCES CORPORATION - FLUR4 - INFLUENZA (SEASONAL) (FLUBLOK QUADRIVALENT)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (OTHER)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - MENB - MENINGOCOCCAL B (TRUMENBA)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MMRV - MEASLES + MUMPS + RUBELLA + VARICELLA (PROQUAD)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MMR - MEASLES + MUMPS + RUBELLA (MMR II)' ||
        $substanceName eq 'CDC - SEQIRUS, INC. - FLUC4 - INFLUENZA (SEASONAL) (FLUCELVAX QUADRIVALENT)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HPV9 - HPV (GARDASIL 9)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - VARZOS - ZOSTER (SHINGRIX)' ||
        $substanceName eq 'CDC - PAXVAX - CHOL - CHOLERA (VAXCHORA)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MU - MUMPS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - VARZOS - ZOSTER (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - HIBV - HIB (ACTHIB)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - MNQHIB - MENINGOCOCCAL C & Y + HIB (MENHIBRIX)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - PNC - PNEUMO (PREVNAR)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TYP - TYPHOID VI POLYSACCHARIDE (TYPHIM VI)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - VARZOS - ZOSTER LIVE (ZOSTAVAX)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - RUB - RUBELLA (MERUVAX II)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - PNC13 - PNEUMO (PREVNAR13)' ||
        $substanceName eq 'ECDC - DIPHTHERIA ANTITOXIN' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HPV4 - HPV (GARDASIL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - RUB - RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MEN - MENINGOCOCCAL (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SEQIRUS, INC. - FLUA4 - INFLUENZA (SEASONAL) (FLUAD QUADRIVALENT)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - PNC20 - PNEUMO (PREVNAR20)' ||
        $substanceName eq 'CDC - LEDERLE PRAXSIS - HIBV - HIB POLYSACCHARIDE (FOREIGN)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - SMALL - SMALLPOX (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MEDIMMUNE VACCINES, INC. - FLUN(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (MEDIMMUNE))' ||
        $substanceName eq 'CDC - MEDIMMUNE VACCINES, INC. - FLUN3 - INFLUENZA (SEASONAL) (FLUENZ)' ||
        $substanceName eq 'CDC - MEDIMMUNE VACCINES, INC. - FLUN4 - INFLUENZA (SEASONAL) (FLUENZ TETRA)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - EBZR - EBOLA ZAIRE (ERVEBO)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MEA - MEASLES (ATTENUVAX)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MEA - MEASLES (FOREIGN)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MEA - MEASLES (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MER - MEASLES + RUBELLA (MR-VAX II)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MM - MEASLES + MUMPS (MM-VAX)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MM - MEASLES + MUMPS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MMR - MEASLES + MUMPS + RUBELLA (MMR I)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MMR - MEASLES + MUMPS + RUBELLA (VIRIVAC)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MU - MUMPS (MUMPSVAX I)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MU - MUMPS (MUMPSVAX II)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MUR - MUMPS + RUBELLA (FOREIGN)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - PNC15 - PNEUMO (VAXNEUVANCE)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - RUB - RUBELLA (MERUVAX I)' ||
        $substanceName eq 'CDC - CSL LIMITED - FLUX - INFLUENZA (SEASONAL) (FOREIGN)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MICHIGAN DEPT PUB HLTH - ANTH - ANTHRAX (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MICHIGAN DEPT PUB HLTH - RAB - RABIES (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MILES LABORATORIES - PLAGUE - PLAGUE (NO BRAND NAME)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (NOVARTIS))' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLU3 - INFLUENZA (SEASONAL) (AGRIFLU)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLU3 - INFLUENZA (SEASONAL) (FLUVIRIN)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLUC3 - INFLUENZA (SEASONAL) (OPTAFLU)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLUX - INFLUENZA (SEASONAL) (FOREIGN)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - RAB - RABIES (RABIVAC)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - RAB - RABIES (RABIPUR)' ||
        $substanceName eq 'CDC - ORGANON-TEKNIKA - BCG - BCG (TICE)' ||
        $substanceName eq 'CDC - PARKDALE PHARMACEUTICALS - FLU3 - INFLUENZA (SEASONAL) (FLUOGEN)' ||
        $substanceName eq 'CDC - PARKE-DAVIS - FLU3 - INFLUENZA (SEASONAL) (FLUOGEN)' ||
        $substanceName eq 'CDC - PASTEUR MERIEUX INST. - RAB - RABIES (IMOVAX ID)' ||
        $substanceName eq 'CDC - PASTEUR MERIEUX INST. - RAB - RABIES (IMOVAX)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - ADEN - ADENOVIRUS (TYPE 4, NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - ADEN - ADENOVIRUS (TYPE 7, NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - CHOL - CHOLERA (USP)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - FLU3 - INFLUENZA (SEASONAL) (FLU-IMUNE)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - FLU3 - INFLUENZA (SEASONAL) (FLUSHIELD)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - HBPV - HIB POLYSACCHARIDE (HIBIMUNE)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - HIBV - HIB (HIBTITER)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - MNC - MENINGOCOCCAL (MENINGITEC)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - PPV - PNEUMO (PNU-IMUNE)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - RV - ROTAVIRUS (ROTASHIELD)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - SMALL - SMALLPOX (DRYVAX)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - TYP - TYPHOID VI POLYSACCHARIDE (ACETONE INACTIVATED DRIED)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - TYP - TYPHOID VI POLYSACCHARIDE (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PROTEIN SCIENCES CORPORATION - FLUR3 - INFLUENZA (SEASONAL) (FLUBLOK)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DF - DENGUE TETRAVALENT (DENGVAXIA)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (SANOFI))' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE INTRADERMAL)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE INTRADERMAL QUADRIVALENT)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - H5N1 - INFLUENZA (SEASONAL) (PANDEMIC FLU VACCINE (H5N1))' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - HIBV - HIB (OMNIHIB)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - HIBV - HIB (PROHIBIT)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - HIBV - HIB (TETRACOQ)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - JEV - JAPANESE ENCEPHALITIS (JE-VAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - RAB - RABIES (IMOVAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - RAB - RABIES (RABIE-VAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - RUB - RUBELLA (RUDIVAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - YF - YELLOW FEVER (STAMARIL)' ||
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - HEPA - HEP A (HAVRIX)' ||
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - LYME - LYME (LYMERIX)' ||
        $substanceName eq 'CDC - TEVA PHARMACEUTICALS - ADEN_4_7 - ADENOVIRUS TYPES 4 & 7, LIVE, ORAL (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - ADEN - ADENOVIRUS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - ANTH - ANTHRAX (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - BCG - BCG (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - CEE - FSME-IMMUN. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - CHOL - CHOLERA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MEA - MEASLES (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MENHIB - MENINGOCOCCAL CONJUGATE + HIB (UNKNOWN)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MER - MEASLES + RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MM - MEASLES + MUMPS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MMRV - MEASLES + MUMPS + RUBELLA + VARICELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MNQ - MENINGOCOCCAL CONJUGATE (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MUR - MUMPS + RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - PER - PERTUSSIS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - PLAGUE - PLAGUE (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - RAB - RABIES (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - SSEV - SUMMER/SPRING ENCEPH (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TBE - TICK-BORNE ENCEPH (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TYP - TYPHOID LIVE ORAL TY21A (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TYP - TYPHOID VI POLYSACCHARIDE (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (FOREIGN)' ||
        $substanceName eq 'CDC - GREER LABORATORIES, INC. - PLAGUE - PLAGUE (USP)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - JEVX - JAPANESE ENCEPHALITIS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - LEDERLE LABORATORIES - CHOL - CHOLERA (USP)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - YF - YELLOW FEVER (YF-VAX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HPVX - HPV (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MEDIMMUNE VACCINES, INC. - FLUN4 - INFLUENZA (SEASONAL) (FLUMIST QUADRIVALENT)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - RAB - RABIES (RABAVERT)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLUC3 - INFLUENZA (SEASONAL) (FLUCELVAX)' ||
        $substanceName eq 'CDC - BERNA BIOTECH, LTD. - TYP - TYPHOID LIVE ORAL TY21A (VIVOTIF)' ||
        $substanceName eq 'CDC - BURROUGHS WELLCOME - RUB - RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - VARCEL - VARICELLA (VARILRIX)' ||
        $substanceName eq 'CDC - INTERCELL AG - JEV1 - JAPANESE ENCEPHALITIS (IXIARO)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - FLUX(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (UNKNOWN))' ||
        $substanceName eq 'CDC - MEDIMMUNE VACCINES, INC. - FLUN3 - INFLUENZA (SEASONAL) (FLUMIST)' ||
        $substanceName eq 'CDC - CONNAUGHT LTD. - RAB - RABIES (IMOVAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HEPA - HEP A (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - JEV - JAPANESE ENCEPHALITIS (J-VAX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HEPA - HEP A (HAVRIX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - MNQ - MENINGOCOCCAL CONJUGATE (MENACTRA)' ||
        $substanceName eq 'CDC - CSL LIMITED - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (CSL))' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - YF - YELLOW FEVER (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LTD. - MEN - MENINGOCOCCAL (MENOMUNE-A/C)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MMR - MEASLES + MUMPS + RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - EMERGENT BIOSOLUTIONS - PER - PERTUSSIS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - MEN - MENINGOCOCCAL (MENOMUNE)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - MNQ - MENINGOCOCCAL CONJUGATE (MENQUADFI)' ||
        $substanceName eq 'CDC - EMERGENT BIOSOLUTIONS - RAB - RABIES (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SEQIRUS, INC. - FLU4 - INFLUENZA (SEASONAL) (AFLURIA QUADRIVALENT)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - SMALL - SMALLPOX (ACAM2000)' ||
        $substanceName eq 'CDC - LEDERLE LABORATORIES - FLU3 - INFLUENZA (SEASONAL) (FLU-IMUNE)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - YF - YELLOW FEVER (YF-VAX)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - TYP - TYPHOID VI POLYSACCHARIDE (TYPHIM VI)' ||
        $substanceName eq 'CDC - EVANS VACCINES - FLU3 - INFLUENZA (SEASONAL) (FLUVIRIN)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - MEN - MENINGOCOCCAL (MENOMUNE)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - EMERGENT BIOSOLUTIONS - ANTH - ANTHRAX (BIOTHRAX)' ||
        $substanceName eq 'CDC - CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (AFLURIA)' ||
        $substanceName eq 'CDC - CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (FLUVAX)' ||
        $substanceName eq 'CDC - CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (NILGRIP)' ||
        $substanceName eq 'CDC - CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (FOREIGN)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE QUADRIVALENT)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (FLUARIX QUADRIVALENT)';
    my $substanceShortenedName;
    if (
        $substanceName eq 'ECDC - HEPATITIS B VACCINE (RDNA)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HIBV - HIB (HIBERIX)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - HIBV - HIB (ACTHIB)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - HIBV - HIB (PROHIBIT)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HBPV - HIB POLYSACCHARIDE (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - HEP - HEP B (GENHEVAC B)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HEP - HEPBC (NO BRAND NAME)' ||
        $substanceName eq 'ECDC - HAEMOPHILUS INFLUENZAE TYPE B (NEISSERIA MENINGITIDIS OUTER MEMBRANE PROTEIN COMPLEX CONJUGATE) AND HEPATITIS B (RECOMBI'
    ) {
        $substanceShortenedName = 'HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'CDC - SANOFI PASTEUR - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SCLAVO - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'ECDC - DIPHTHERIA VACCINE (ADSORBED)' ||
        $substanceName eq 'CDC - MICHIGAN DEPT PUB HLTH - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DT - DT ADSORBED (DITANRIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTOX - DIPHTHERIA TOXOIDS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LTD. - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - BSI - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - LEDERLE LABORATORIES - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - EMERGENT BIOSOLUTIONS - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MASS. PUB HLTH BIOL LAB - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DT - DT ADSORBED (DECAVAC)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DT - DT ADSORBED (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS AND HEPATITIS B (RDNA) VACCINE (ADSORBED)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS AND HEPATITIS B VACCINE';
    } elsif (
        $substanceName eq 'ECDC - POLIOMYELITIS VACCINE (INACTIVATED)' ||
        $substanceName eq 'CDC - PASTEUR MERIEUX CONNAUGHT - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - IPV - POLIO VIRUS, INACT. (IPOL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - IPV - POLIO VIRUS, INACT. (POLIOVAX)' ||
        $substanceName eq 'CDC - PASTEUR MERIEUX INST. - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - OPV - POLIO VIRUS, ORAL (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'POLIOMYELITIS (IPV) VACCINE';
    } elsif (
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - OPV - POLIO VIRUS, ORAL (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - OPV - POLIO VIRUS, ORAL (ORIMUNE)' ||
        $substanceName eq 'CDC - CONNAUGHT LTD. - IPV - POLIO VIRUS, INACT. (POLIOVAX)'
    ) {
        $substanceShortenedName = 'POLIOMYELITIS (OPV) VACCINE';
    } elsif (
        $substanceName eq 'ECDC - TETANUS VACCINES' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - BERNA BIOTECH, LTD. - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - TTOX - TETANUS TOXOID (TEVAX)' ||
        $substanceName eq 'CDC - EMERGENT BIOSOLUTIONS - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - LEDERLE LABORATORIES - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CDC - LEDERLE LABORATORIES - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MASS. PUB HLTH BIOL LAB - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MEDEVA PHARMA, LTD. - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MICHIGAN DEPT PUB HLTH - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SCLAVO - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SCLAVO - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'TETANUS VACCINE';
    } elsif (
        $substanceName eq 'CDC - MERCK & CO. INC. - HBHEPB - HIB + HEP B (COMVAX)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HEP - HEP B (FOREIGN)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HBHEPB - HIB + HEP B (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'HAEMOPHILIUS B & HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HEPAB - HEP A + HEP B (NO BRAND NAME)' ||
        $substanceName eq 'CDC - DYNAVAX TECHNOLOGIES CORPORATION - HEP - HEP B (HEPLISAV-B)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HEP - HEP B (ENGERIX-B)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HEP - HEP B (RECOMBIVAX HB)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HEP - HEP B (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HEPAB - HEP A + HEP B (TWINRIX)' ||
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - HEP - HEP B (ENGERIX-B)' ||
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - HEPAB - HEP A + HEP B (TWINRIX)'
    ) {
        $substanceShortenedName = 'HEPATITE A & HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS AND POLIOMYELITIS (INACTIVATED) VACCINE (ADSORBED, REDUCED ANTIGEN(S) CONTENT)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAPIPV - DTAP + IPV (QUADRACEL)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTPIPV - DTP + IPV (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAPIPV - DTAP + IPV (UNKNOWN)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTPIPV - DTP + IPV (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - 6VAX-F - DTAP+IPV+HEPB+HIB (HEXAVAC)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTIPV - DT + IPV (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - DTAP - DTAP (TRIPEDIA)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTPHIB - DTP + HIB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - DTAP - DTAP (ACEL-IMUNE)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - TDAPIPV - TDAP + IPV (FOREIGN)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TDAPIPV - TDAP + IPV (DOMESTIC)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAPIPV - DTAP + IPV (INFANRIX TETRA)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS & POLIOMYELITIS VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA AND TETANUS VACCINE (ADSORBED)' ||
        $substanceName eq 'CDC - MICHIGAN DEPT PUB HLTH - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - TDAP - TDAP (BOOSTRIX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TDAP - TDAP (ADACEL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TDAP - TDAP (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MASS. PUB HLTH BIOL LAB - TD - TD ADSORBED (TDVAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TD - TD ADSORBED (TENIVAC)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - TD - TD ADSORBED (TD-RIX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - TD - TD ADSORBED (DITANRIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TD - TETANUS DIPHTHERIA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - LEDERLE LABORATORIES - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - AVENTIS PASTEUR - TD - TETANUS DIPHTHERIA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SCLAVO - TD - TD ADSORBED (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA & TETANUS VACCINE';
    } elsif (
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - DTAP - DTAP (INFANRIX)'                                                    ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAP - DTAP (DAPTACEL)'                                                        ||
        $substanceName eq 'CDC - NORTH AMERICAN VACCINES - DTAP - DTAP (CERTIVA)'                                                ||
        $substanceName eq 'CDC - LEDERLE LABORATORIES - DTP - DTP (TRI-IMMUNOL)'                                                 ||
        $substanceName eq 'CDC - PFIZER\WYETH - DTP - DTP (NO BRAND NAME)'                                                       ||
        $substanceName eq 'CDC - MICHIGAN DEPT PUB HLTH - DTP - DTP (NO BRAND NAME)'                                             ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTP - DTP (NO BRAND NAME)'                                                     ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - DPP - DIPHTHERIA TOXOID + PERTUSSIS + IPV (QUATRO VIRELON)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DPP - DIPHTHERIA TOXOID + PERTUSSIS + IPV (NO BRAND NAME)'               ||
        $substanceName eq 'CDC - MASS. PUB HLTH BIOL LAB - DTP - DTP (NO BRAND NAME)'                                            ||
        $substanceName eq 'CDC - CONNAUGHT LABORATORIES - DTP - DTP (NO BRAND NAME)'                                             ||
        $substanceName eq 'CDC - BAXTER HEALTHCARE CORP. - DTAP - DTAP (CERTIVA)'                                                ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAP - DTAP (NO BRAND NAME)'                                             ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS AND PERTUSSIS (ACELLULAR, COMPONENT) VACCINE (ADSORBED)'                   ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAP - DTAP (INFANRIX)'                                           ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTP - DTP (NO BRAND NAME)'                                               ||
        $substanceName eq 'CDC - EMERGENT BIOSOLUTIONS - DTP - DTP (NO BRAND NAME)'                                              ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAP - DTAP (TRIPEDIA)'
    ) {
        $substanceShortenedName = 'DIPHTERIA, TETANUS & PERTUSSIS VACCINE';
    } elsif (
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAPIPVHIB - DTAP + IPV + HIB (PENTACEL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTPIHI - DT+IPV+HIB+HEPB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - 6VAX-F - DTAP+IPV+HEPB+HIB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAPHEPBIP - DTAP + HEPB + IPV (INFANRIX PENTA)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAPHEPBIP - DTAP + HEPB + IPV (PEDIARIX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAPIPV - DTAP + IPV (KINRIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAPH - DTAP + HIB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAPIPVHIB - DTAP + IPV + HIB (UNKNOWN)' ||
        $substanceName eq 'CDC - MSP VACCINE COMPANY - DTPPVHBHPB - DTAP+IPV+HIB+HEPB (VAXELIS)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAPHEPBIP - DTAP + HEPB + IPV (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAPH - DTAP + HIB (TRIHIBIT)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTPPHIB - DTP + IPV + ACT-HIB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAPIPVHIB - DTAP + IPV + HIB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - BERNA BIOTECH, LTD. - DTPIPV - DTP + IPV (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - DTPHIB - DTP + HIB (TETRAMUNE)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTPHIB - DTP + HIB (DTP + ACTHIB)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAPIPVHIB - DTAP + IPV + HIB (INFANRIX QUINTA)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - 6VAX-F - DTAP+IPV+HEPB+HIB (INFANRIX HEXA)'
    ) {
        $substanceShortenedName = 'DIPHTERIA, TETANUS, WHOOPING COUGH, POLIOMYELITIS & HAEMOPHILIUS INFLUENZA TYPE B VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT) AND POLIOMYELITIS (INACTIVATED) VACCINE (ADSORBED)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS & POLIOMYELITIS VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT), HEPATITIS B (RDNA), POLIOMYELITIS (INACT.) AND HAEMOPHILUS TYPE B' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT), POLIOMYELITIS (INACTIVATED) AND HAEMOPHILUS TYPE B CONJUGATE VACC' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS, HEPATITIS B (RDNA) AND HAEMOPHILUS INFLUENZAE TYPE B CONJUGATE VACCINE (ADSORBED)' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT) AND HAEMOPHILUS TYPE B CONJUGATE VACCINE (ADSORBED)' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS, HEPATITIS B (RDNA), POLIOMYELITIS & HAEMOPHILUS TYPE B VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT), HEPATITIS B (RDNA), POLIOMYELITIS (INACTIVATED) VACCINE (ADSORBED' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS, HEPATITIS B (RDNA) & POLIOMYELITIS VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT) AND HEPATITIS B (RDNA) VACCINE (ADSORBED)' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS AND HEPATITIS B (RDNA) VACCINE (ADSORBED)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTPHEP - DTP + HEP B (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTPHEP - DTP + HEP B (TRITANRIX)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS & HEPATITIS B (RDNA) VACCINE';
    } elsif (
        $substanceName eq 'CDC - JANSSEN - COVID19 - COVID19 (COVID19 (JANSSEN))' ||
        $substanceName eq 'ECDC - COVID-19 VACCINE JANSSEN (AD26.COV2.S)'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE JANSSEN';
    } elsif (
        $substanceName eq 'CDC - MODERNA - COVID19 - COVID19 (COVID19 (MODERNA))' ||
        $substanceName eq 'ECDC - COVID-19 MRNA VACCINE MODERNA (CX-024414)'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE MODERNA';
    } elsif (
        $substanceName eq 'ECDC - TETANUS TOXOID, SALMONELLA TYPHI BACTERIA (INACTIVATED)'
    ) {
        $substanceShortenedName = 'TETANUS, SALMONELLA, TYPHUS BACTERIA VACCINE';
    } elsif (
        $substanceName eq 'CDC - PFIZER\BIONTECH - COVID19 - COVID19 (COVID19 (PFIZER-BIONTECH))' ||
        $substanceName eq 'ECDC - COVID-19 MRNA VACCINE PFIZER-BIONTECH (TOZINAMERAN)'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE PFIZER-BIONTECH';
    } elsif ($substanceName eq 'CDC - UNKNOWN MANUFACTURER - COVID19 - COVID19 (COVID19 (UNKNOWN))') {
        $substanceShortenedName = 'COVID-19 VACCINE UNKNOWN MANUFACTURER';
    } elsif ($substanceName eq 'ECDC - COVID-19 VACCINE ASTRAZENECA (CHADOX1 NCOV-19)') {
        $substanceShortenedName = 'COVID-19 VACCINE ASTRAZENECA';
    } elsif ($substanceName eq 'ECDC - COVID-19 VACCINE NOVAVAX (NVX-COV2373)') {
        $substanceShortenedName = 'COVID-19 VACCINE NOVAVAX';
    } else {
    	$unknownSubstances{$substanceName} = 1;
        say "unknown : substanceName : $substanceName";
        return 0;
    }
    my $substanceCategory;
    if ($substanceShortenedName =~ /COVID-19/) {
        $substanceCategory = 'COVID-19';
    } else {
        $substanceCategory = 'OTHER'
    }
    return ($substanceCategory, $substanceShortenedName);
}

sub print_reports {
	say "printing deaths abstract ...";
	my $dataFolder = 'unified_data';
	for my $date (sort{$a <=> $b} keys %reports) {
		make_path("$dataFolder/$date") unless (-d "$dataFolder/$date");
		my @obj = \@{$reports{$date}};
		open my $outReports, '>:utf8', "$dataFolder/$date/data.json";
		my $reports = encode_json\@obj;
		say $outReports $reports;
		close $outReports;
	}
}