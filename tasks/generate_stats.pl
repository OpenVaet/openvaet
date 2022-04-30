#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use JSON;
use FindBin;
use lib "$FindBin::Bin/../lib";

# Project's libraries.
use global;
use config;
use time;

# Sources to be updated.
my $ecdcSourceId = 1;
my $cdcSourceId = 2;

# Initiating arrays which will contain the merged reports.
my @serious               = ();
my @deaths                = ();
my @nonSerious            = ();
my %stats                 = ();

# Initiating ECDC cache data.
my %ecdcDrugs             = ();
my %ecdcDrugsNotices      = ();
my %ecdcReactions         = ();
my %ecdcReactionsOutcomes = ();
my %ecdcNoticeReactions   = ();
my %cdcSymptoms           = ();
my %cdcVaccines           = ();

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
	    next unless keys %{$ecdcDrugsNotices{$ecdcNoticeId}}; # Happens when we are indexing deaths live in parallel only.
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
	        my %dObj = ();
	        $dObj{'drugName'} = $ecdcDrugName;
	        push @{$obj{'substances'}}, \%dObj;
	        if ($ecdcDrugName =~ /COVID/) {
	        	$isCovid = 1;
	        } else {
	        	$isOtherVaccine = 1;
	        }
	    }

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
	    if ($isOtherVaccine && $isCovid) {
	    	$isOtherVaccinePlusCovid = 1;
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

	    if ($hasDied == 1) {
	    	$obj{'patientDied'}              = 1;
	    	push @deaths, \%obj;
	    	$stats{'eventsCategorized'}->{'deaths'}->{$ecdcYearName}->{$ecdcReporterTypeName}->{$ecdcAgeGroupName}->{$ecdcSexName}->{$statSection}++;
		    for my $ecdcDrugId (sort{$a <=> $b} keys %{$ecdcDrugsNotices{$ecdcNoticeId}}) {
		        my $ecdcDrugName = $ecdcDrugs{$ecdcDrugId}->{'ecdcDrugName'} // die;
	    		$stats{'drugsCategorized'}->{'deaths'}->{$ecdcYearName}->{$ecdcReporterTypeName}->{$ecdcAgeGroupName}->{$ecdcSexName}->{"ECDC - $ecdcDrugName"}++;
		    }
	    	# last if $stats{'eventsCategorized'}->{'deaths'}->{$ecdcYearName}->{$ecdcReporterTypeName}->{$ecdcAgeGroupName}->{$ecdcSexName} == 10;
		} elsif ($isSerious == 1) {
	    	$obj{'patientDied'}              = 0;
	    	push @serious, \%obj;
	    	$stats{'eventsCategorized'}->{'serious'}->{$ecdcYearName}->{$ecdcReporterTypeName}->{$ecdcAgeGroupName}->{$ecdcSexName}->{$statSection}++;
		    for my $ecdcDrugId (sort{$a <=> $b} keys %{$ecdcDrugsNotices{$ecdcNoticeId}}) {
		        my $ecdcDrugName = $ecdcDrugs{$ecdcDrugId}->{'ecdcDrugName'} // die;
	    		$stats{'drugsCategorized'}->{'serious'}->{$ecdcYearName}->{$ecdcReporterTypeName}->{$ecdcAgeGroupName}->{$ecdcSexName}->{"ECDC - $ecdcDrugName"}++;
		    }
		} else {
	    	$obj{'patientDied'}              = 0;
			push @nonSerious, \%obj;
	    	$stats{'eventsCategorized'}->{'nonSerious'}->{$ecdcYearName}->{$ecdcReporterTypeName}->{$ecdcAgeGroupName}->{$ecdcSexName}->{$statSection}++;
		    for my $ecdcDrugId (sort{$a <=> $b} keys %{$ecdcDrugsNotices{$ecdcNoticeId}}) {
		        my $ecdcDrugName = $ecdcDrugs{$ecdcDrugId}->{'ecdcDrugName'} // die;
	    		$stats{'drugsCategorized'}->{'nonSerious'}->{$ecdcYearName}->{$ecdcReporterTypeName}->{$ecdcAgeGroupName}->{$ecdcSexName}->{"ECDC - $ecdcDrugName"}++;
		    }
		}
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
        if ($patientDied == 1) {
            $patientDied = 'Yes';
        } elsif ($patientDied == 0) {
            $patientDied = 'No';
        } else {
            die "patientDied : $patientDied";
        }
        if ($lifeThreatning == 1) {
            $lifeThreatning = 'Yes';
        } elsif ($lifeThreatning == 0) {
            $lifeThreatning = 'No';
        } else {
            die "lifeThreatning : $lifeThreatning";
        }
        if ($hospitalized == 1) {
            $hospitalized = 'Yes';
        } elsif ($hospitalized == 0) {
            $hospitalized = 'No';
        } else {
            die "hospitalized : $hospitalized";
        }
        if ($permanentDisability == 1) {
            $permanentDisability = 'Yes';
        } elsif ($permanentDisability == 0) {
            $permanentDisability = 'No';
        } else {
            die "permanentDisability : $permanentDisability";
        }
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
            # say "cdcVaccineTypeName : $cdcVaccineTypeName";
            if ($cdcVaccineTypeName eq 'COVID19') {
            	$isCovid = 1;
            } else {
            	if ($cdcVaccineName =~ /TETANUS/) {
            		$isOtherVaccine = 1;
            	} elsif ($cdcVaccineName =~ /DIPHTERIA/) {
            		$isOtherVaccine = 1;
            	} elsif ($cdcVaccineName =~ /HEP B/) {
            		$isOtherVaccine = 1;
            	} elsif ($cdcVaccineName =~ /POLIO/) {
            		$isOtherVaccine = 1;
            	}
            }
            my $drugName = "$cdcManufacturerName - $cdcVaccineTypeName - $cdcVaccineName";
            my %o               = ();
            $o{'drugName'}      = $drugName;
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
        $obj{'source'}                   = $source;
        $obj{'seriousnessName'}          = $seriousnessName;
        $obj{'reference'}                = "$reference-1";
        $obj{'source'}                   = $source;
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
	    if ($patientDied eq 'Yes') {
	    	push @deaths, \%obj;
	    	$stats{'eventsCategorized'}->{'deaths'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$statSection}++;
	    	# last if $stats{'eventsCategorized'}->{'deaths'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$statSection} == 10;
		    for my $cdcVaccineId (sort{$a <=> $b} keys %$cRVTb) {
		        my $cdcVaccineName      = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineName'}      // die;
		        my $cdcManufacturerId   = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerId'}   // die;
		        my $cdcManufacturerName = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerName'} // die;
		        my $cdcVaccineTypeId    = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeId'}    // die;
		        my $cdcVaccineTypeName  = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeName'}  // die;
		        my $drugName = "$cdcManufacturerName - $cdcVaccineTypeName - $cdcVaccineName";
	    		$stats{'drugsCategorized'}->{'deaths'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{"CDC - $drugName"}++;
		    }
		} elsif ($seriousnessName eq 'Serious') {
	    	push @serious, \%obj;
	    	$stats{'eventsCategorized'}->{'serious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$statSection}++;
		    for my $cdcVaccineId (sort{$a <=> $b} keys %$cRVTb) {
		        my $cdcVaccineName      = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineName'}      // die;
		        my $cdcManufacturerId   = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerId'}   // die;
		        my $cdcManufacturerName = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerName'} // die;
		        my $cdcVaccineTypeId    = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeId'}    // die;
		        my $cdcVaccineTypeName  = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeName'}  // die;
		        my $drugName = "$cdcManufacturerName - $cdcVaccineTypeName - $cdcVaccineName";
	    		$stats{'drugsCategorized'}->{'serious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{"CDC - $drugName"}++;
		    }
		} else {
	        # p%obj;
	        # die;
			push @nonSerious, \%obj;
	    	$stats{'eventsCategorized'}->{'nonSerious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$statSection}++;
		    for my $cdcVaccineId (sort{$a <=> $b} keys %$cRVTb) {
		        my $cdcVaccineName      = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineName'}      // die;
		        my $cdcManufacturerId   = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerId'}   // die;
		        my $cdcManufacturerName = $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerName'} // die;
		        my $cdcVaccineTypeId    = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeId'}    // die;
		        my $cdcVaccineTypeName  = $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeName'}  // die;
		        my $drugName = "$cdcManufacturerName - $cdcVaccineTypeName - $cdcVaccineName";
	    		$stats{'drugsCategorized'}->{'nonSerious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{"CDC - $drugName"}++;
		    }
		}
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
	my $seriousnessName;
	if ($patientDied eq 'Yes' || $lifeThreatning eq 'Yes' || $hospitalized eq 'Yes' || $permanentDisability eq 'Yes') {
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

sub print_reports {
	say "printing deaths abstract ...";
	open my $outDeaths, '>:utf8', 'deaths.json';
	my $deaths = encode_json\@deaths;
	say $outDeaths $deaths;
	close $outDeaths;

	say "printing serious abstract ...";
	open my $outSerious, '>:utf8', 'serious.json';
	my $serious = encode_json\@serious;
	say $outSerious $serious;
	close $outSerious;

	say "printing non-serious abstract ...";
	open my $outNonSerious, '>:utf8', 'nonSerious.json';
	my $nonSerious = encode_json\@nonSerious;
	say $outNonSerious $nonSerious;
	close $outNonSerious;

	say "printing chart stats abstract ...";
	open my $outStats, '>:utf8', 'stats.json';
	my $stats = encode_json\%stats;
	say $outStats $stats;
	close $outStats;
}