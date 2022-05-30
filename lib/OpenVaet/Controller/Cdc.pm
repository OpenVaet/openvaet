package OpenVaet::Controller::Cdc;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

sub cdc {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;
    my $cdcSourceId     = 2;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching total reports.
    my $tb1 = $self->dbh->selectrow_hashref("SELECT totalReports FROM source WHERE id = $cdcSourceId", undef);
    my $totalReports = %$tb1{'totalReports'} // die;

    $self->render(
        environment     => $environment,
        totalReports    => $totalReports,
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub state_year_reports {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching states for filtering.
    my %cdcStates = ();
    my $cSTb = $self->dbh->selectall_hashref("SELECT id as cdcStateId, name as cdcStateName FROM cdc_state", 'cdcStateId');
    for my $cdcStateId (sort{$a <=> $b} keys %$cSTb) {
        my $cdcStateName = %$cSTb{$cdcStateId}->{'cdcStateName'} // die;
        $cdcStates{$cdcStateName}->{'cdcStateId'} = $cdcStateId;
    }

    # Fetching years for filtering.
    my %cdcYears = ();
    my $cYTb = $self->dbh->selectall_hashref("SELECT DISTINCT year FROM cdc_state_year", 'year');
    %cdcYears = %$cYTb;

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages,
        cdcStates       => \%cdcStates,
        cdcYears        => \%cdcYears
    );
}

sub load_state_years {
    my $self = shift;
    my $cdcStateId = $self->param('cdcStateId');
    my $cdcYear = $self->param('cdcYear');
    say "cdcStateId : $cdcStateId";
    say "cdcYear : $cdcYear";
    my $sql = "
        SELECT 
            cdc_state_year.id as cdcStateYearId,
            cdc_state.name as cdcStateName,
            cdc_state_year.year,
            cdc_state_year.totalReports,
            cdc_state_year.updateTimestamp
        FROM cdc_state_year
            LEFT JOIN cdc_state ON cdc_state.id = cdc_state_year.cdcStateId";
    my $hasCondition = 0;
    if ($cdcStateId || $cdcYear) {
        $sql .= "
        WHERE
        ";
    }
    if ($cdcStateId) {
        $hasCondition = 1;
        $sql .= "
            cdc_state_year.cdcStateId = $cdcStateId
        ";
    }
    if ($cdcYear) {
        if ($hasCondition) {
            $sql .= " AND ";
        }
        $hasCondition = 1;
        $sql .= "
            cdc_state_year.year = $cdcYear
        ";
    }
    say "sql : $sql";
    my $tb = $self->dbh->selectall_hashref($sql, 'cdcStateYearId');
    my @stateYears = ();
    for my $cdcStateYearId (sort{$a <=> $b} keys %$tb) {
        my $cdcStateName    = %$tb{$cdcStateYearId}->{'cdcStateName'}    // die;
        my $year            = %$tb{$cdcStateYearId}->{'year'}            // die;
        my $totalReports    = %$tb{$cdcStateYearId}->{'totalReports'}    // die;
        my $updateTimestamp = %$tb{$cdcStateYearId}->{'updateTimestamp'} // die;
        my $updateDatetime  = time::timestamp_to_datetime($updateTimestamp);
        my %obj = ();
        $obj{'cdcStateYearId'}  = $cdcStateYearId;
        $obj{'cdcStateName'}    = $cdcStateName;
        $obj{'year'}            = $year;
        $obj{'totalReports'}    = $totalReports;
        $obj{'updateDatetime'}  = $updateDatetime;
        push @stateYears, \%obj;
    }

    $self->render(
        stateYears => \@stateYears
    );
}

sub notices {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        environment     => $environment,
        currentLanguage => $currentLanguage,
        languages       => \%languages,
    );
}

sub load_notices_filters {
    my $self = shift;

    my %enums = %{$self->enums()};
    # p%enums;
    my %forms = ();
    for my $ecdcGeographicalOrigin (sort keys %{$enums{'ecdcGeographicalOrigin'}}) {
        my $ecdcGeographicalOriginName = $enums{'ecdcGeographicalOrigin'}->{$ecdcGeographicalOrigin} // die;
        $forms{'ecdcGeographicalOrigin'}->{$ecdcGeographicalOriginName} = $ecdcGeographicalOrigin;
    }
    for my $ecdcAgeGroup (sort keys %{$enums{'ecdcAgeGroup'}}) {
        my $ecdcAgeGroupName = $enums{'ecdcAgeGroup'}->{$ecdcAgeGroup} // die;
        $forms{'ecdcAgeGroup'}->{$ecdcAgeGroup} = $ecdcAgeGroupName;
    }

    # Listing sexes stored.
    my $cSxTb = $self->dbh->selectall_hashref("SELECT id as cdcSexId, name as cdcSexName FROM cdc_sexe", 'cdcSexId');
    for my $cdcSexId (sort{$a <=> $b} keys %$cSxTb) {
        my $cdcSexName = %$cSxTb{$cdcSexId}->{'cdcSexName'} // die;
        $forms{'cdcSex'}->{$cdcSexId} = $cdcSexName;
    }

    # Listing states stored.
    my $cSTb = $self->dbh->selectall_hashref("SELECT id as cdcStateId, name as cdcStateName FROM cdc_state", 'cdcStateId');
    for my $cdcStateId (sort{$a <=> $b} keys %$cSTb) {
        my $cdcStateName = %$cSTb{$cdcStateId}->{'cdcStateName'} // die;
        $forms{'cdcState'}->{$cdcStateName}->{'cdcStateId'} = $cdcStateId;
    }

    # Listing manufacturers stored.
    my $cMTb = $self->dbh->selectall_hashref("SELECT id as cdcManufacturerId, name as cdcManufacturerName FROM cdc_manufacturer", 'cdcManufacturerId');
    for my $cdcManufacturerId (sort{$a <=> $b} keys %$cMTb) {
        my $cdcManufacturerName = %$cMTb{$cdcManufacturerId}->{'cdcManufacturerName'} // die;
        $forms{'cdcManufacturer'}->{$cdcManufacturerName}->{'cdcManufacturerId'} = $cdcManufacturerId;
    }

    # Listing vaccine types stored.
    my $cVTTb = $self->dbh->selectall_hashref("SELECT id as cdcVaccineTypeId, name as cdcVaccineTypeName FROM cdc_vaccine_type", 'cdcVaccineTypeId');
    for my $cdcVaccineTypeId (sort{$a <=> $b} keys %$cVTTb) {
        my $cdcVaccineTypeName = %$cVTTb{$cdcVaccineTypeId}->{'cdcVaccineTypeName'} // die;
        $forms{'cdcVaccineType'}->{$cdcVaccineTypeName}->{'cdcVaccineTypeId'} = $cdcVaccineTypeId;
    }

    # Listing vaccine stored.
    my $cVTb = $self->dbh->selectall_hashref("SELECT id as cdcVaccineId, name as cdcVaccineName FROM cdc_vaccine", 'cdcVaccineId');
    for my $cdcVaccineId (sort{$a <=> $b} keys %$cVTb) {
        my $cdcVaccineName = %$cVTb{$cdcVaccineId}->{'cdcVaccineName'} // die;
        $forms{'cdcVaccine'}->{$cdcVaccineName}->{'cdcVaccineId'} = $cdcVaccineId;
    }

    # Listing symptoms stored.
    my $eRTb = $self->dbh->selectall_hashref("SELECT id as cdcSymptomId, name as cdcSymptomName FROM cdc_symptom", 'cdcSymptomId');
    for my $cdcSymptomId (sort{$a <=> $b} keys %$eRTb) {
        my $cdcSymptomName = %$eRTb{$cdcSymptomId}->{'cdcSymptomName'} // die;
        $forms{'cdcSymptom'}->{$cdcSymptomName}->{'cdcSymptomId'} = $cdcSymptomId;
    }

    $self->render(
        forms => \%forms
    );
}

sub load_notices {
    my $self                = shift;
    my $pageNumber          = $self->param('pageNumber') // die;
    my $cdcStateId          = $self->param('cdcStateId');
    my $cdcSex              = $self->param('cdcSex');
    my $fromAge             = $self->param('fromAge');
    my $toAge               = $self->param('toAge');
    my $noticeSearch        = $self->param('noticeSearch');
    my $permanentDisability = $self->param('permanentDisability');
    my $lifeThreatning      = $self->param('lifeThreatning');
    my $hospitalized        = $self->param('hospitalized');
    my $cdcVaccineTypeId    = $self->param('cdcVaccineTypeId');
    my $patientDied         = $self->param('patientDied');
    my $cdcVaccineId        = $self->param('cdcVaccineId');
    my $cdcSymptomId        = $self->param('cdcSymptomId');
    my $cdcManufacturerId   = $self->param('cdcManufacturerId');
    my $covidVaccinesOnly   = $self->param('covidVaccinesOnly');
    my %enums               = %{$self->enums()};
    say "pageNumber          : $pageNumber";
    say "cdcStateId          : $cdcStateId";
    say "cdcSex              : $cdcSex";
    say "fromAge             : $fromAge";
    say "toAge               : $toAge";
    say "noticeSearch        : $noticeSearch";
    say "permanentDisability : $permanentDisability";
    say "lifeThreatning      : $lifeThreatning";
    say "cdcVaccineTypeId    : $cdcVaccineTypeId";
    say "patientDied         : $patientDied";
    say "cdcVaccineId        : $cdcVaccineId";
    say "cdcSymptomId        : $cdcSymptomId";
    say "cdcManufacturerId   : $cdcManufacturerId";
    say "covidVaccinesOnly   : $covidVaccinesOnly";

    # Fetching symptoms.
    my %cdcSymptoms = ();
    my $cSTb = $self->dbh->selectall_hashref("SELECT id as cdcSymptomId, name as cdcSymptomName FROM cdc_symptom", 'cdcSymptomId');
    for my $cdcSymptomId (sort{$a <=> $b} keys %$cSTb) {
        my $cdcSymptomName = %$cSTb{$cdcSymptomId}->{'cdcSymptomName'} // die;
        $cdcSymptoms{$cdcSymptomId}->{'cdcSymptomName'} = $cdcSymptomName;
    }

    # Fetching vaccines.
    my %cdcVaccines = ();
    my $cVTb = $self->dbh->selectall_hashref("
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
            LEFT JOIN cdc_sexe ON cdc_sexe.id = cdc_report.cdcSexeId
        WHERE
            cdc_report.id IS NOT NULL";
    if ($cdcStateId) {
        $sql .= " AND cdcStateId = $cdcStateId";
    }
    if ($cdcSex) {
        $sql .= " AND cdcSexeId = $cdcSex";
    }
    if ($fromAge) {
        $sql .= " AND patientAge >= $fromAge";
    }
    if ($toAge) {
        $sql .= " AND patientAge <= $toAge";
    }
    if ($patientDied) {
        $sql .= " AND cdc_report.patientDied = 1" if $patientDied == 1;
        $sql .= " AND cdc_report.patientDied = 0" if $patientDied == 2;
    }
    if ($lifeThreatning) {
        $sql .= " AND cdc_report.lifeThreatning = 1" if $lifeThreatning == 1;
        $sql .= " AND cdc_report.lifeThreatning = 0" if $lifeThreatning == 2;
    }
    if ($hospitalized) {
        $sql .= " AND cdc_report.hospitalized = 1" if $hospitalized == 1;
        $sql .= " AND cdc_report.hospitalized = 0" if $hospitalized == 2;
    }
    if ($permanentDisability) {
        $sql .= " AND cdc_report.permanentDisability = 1" if $permanentDisability == 1;
        $sql .= " AND cdc_report.permanentDisability = 0" if $permanentDisability == 2;
    }
    say $sql;
    my $tb        = $self->dbh->selectall_hashref($sql, 'cdcReportId');
    my $toEntry   = $pageNumber * 50;
    my $fromEntry = $toEntry - 49;
    say "from : $fromEntry -> to : $toEntry";
    my $totalEcdcReports = 0;
    for my $cdcReportId (sort{$a <=> $b} keys %$tb) {
        $totalEcdcReports++;
        if ($totalEcdcReports >= $fromEntry && $totalEcdcReports <= $toEntry) {
            # Filtering by vaccine, type or manufacturer if required.
            if ($cdcVaccineTypeId || $cdcManufacturerId || $cdcVaccineId) {
                my $hasVaccineType = 0;
                my $hasVaccine     = 0;
                my $cRVTb = $self->dbh->selectall_hashref("SELECT cdcVaccineId, dose FROM cdc_report_vaccine WHERE cdcReportId = $cdcReportId", 'cdcVaccineId') or die $!;
                next unless keys %$cRVTb;
                for my $cVId (sort{$a <=> $b} keys %$cRVTb) {
                    my $cdcVaccineName      = $cdcVaccines{$cVId}->{'cdcVaccineName'}      // die;
                    my $cMId                = $cdcVaccines{$cVId}->{'cdcManufacturerId'}   // die;
                    my $cdcManufacturerName = $cdcVaccines{$cVId}->{'cdcManufacturerName'} // die;
                    my $cVTId               = $cdcVaccines{$cVId}->{'cdcVaccineTypeId'}    // die;
                    my $cdcVaccineTypeName  = $cdcVaccines{$cVId}->{'cdcVaccineTypeName'}  // die;
                    if ($cdcVaccineTypeId) {
                        $hasVaccineType = 1 if $cdcVaccineTypeId == $cVTId;
                    }
                    if ($cdcVaccineId) {
                        $hasVaccine = 1 if $cdcVaccineId == $cVId;
                    }

                }
                if ($cdcVaccineTypeId) {
                    unless ($hasVaccineType == 1) {
                        $totalEcdcReports--;
                        next;
                    }
                }
                if ($cdcVaccineId) {
                    unless ($hasVaccine == 1) {
                        $totalEcdcReports--;
                        next;
                    }
                }
            }
            # Filtering by symptom if required.
            if ($cdcSymptomId) {
                my $hasSymptom = 0;
                my $cRSTb = $self->dbh->selectall_hashref("SELECT cdcSymptomId FROM cdc_report_symptom WHERE cdcReportId = $cdcReportId", 'cdcSymptomId') or die $!;
                next unless keys %$cRSTb;
                for my $cSId (sort{$a <=> $b} keys %$cRSTb) {
                    $hasSymptom = 1 if $cdcSymptomId == $cSId;
                }
                if ($cdcSymptomId) {
                    unless ($hasSymptom == 1) {
                        $totalEcdcReports--;
                        next;
                    }
                }
            }
            my $cdcStateId                   = %$tb{$cdcReportId}->{'cdcStateId'}          // die;
            my $cdcStateName                 = %$tb{$cdcReportId}->{'cdcStateName'}        // die;
            my $internalId                   = %$tb{$cdcReportId}->{'internalId'}          // die;
            my $vaccinationDate              = %$tb{$cdcReportId}->{'vaccinationDate'};
            my $cdcReceptionDate             = %$tb{$cdcReportId}->{'cdcReceptionDate'};
            my $cdcSex                       = %$tb{$cdcReportId}->{'cdcSex'}              // die;
            my $cdcSexName                   = %$tb{$cdcReportId}->{'cdcSexName'}          // die;
            my $patientAge                   = %$tb{$cdcReportId}->{'patientAge'};
            my $aEDescription                = %$tb{$cdcReportId}->{'aEDescription'};
            my $patientDied                  = %$tb{$cdcReportId}->{'patientDied'}         // die;
            my $lifeThreatning               = %$tb{$cdcReportId}->{'lifeThreatning'}      // die;
            my $hospitalized                 = %$tb{$cdcReportId}->{'hospitalized'}        // die;
            my $permanentDisability          = %$tb{$cdcReportId}->{'permanentDisability'} // die;
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
            my %obj = ();
            $obj{'cdcStateId'}               = $cdcStateId;
            $obj{'cdcStateName'}             = $cdcStateName;
            $obj{'internalId'}               = "$internalId-1";
            $obj{'vaccinationDate'}          = $vaccinationDate;
            $obj{'cdcReceptionDate'}         = $cdcReceptionDate;
            $obj{'cdcSex'}                   = $cdcSex;
            $obj{'aEDescription'}            = $aEDescription;
            $obj{'cdcSexName'}               = $cdcSexName;
            $obj{'patientAge'}               = $patientAge;
            $obj{'patientDied'}              = $patientDied;
            $obj{'lifeThreatning'}           = $lifeThreatning;
            $obj{'hospitalized'}             = $hospitalized;
            $obj{'permanentDisability'}      = $permanentDisability;

            # Integrating symptoms related to the report.
            my $cRSTb = $self->dbh->selectall_hashref("SELECT cdcSymptomId FROM cdc_report_symptom WHERE cdcReportId = $cdcReportId", 'cdcSymptomId') or die $!;
            for my $cSId (sort{$a <=> $b} keys %$cRSTb) {
                my $cdcSymptomName = $cdcSymptoms{$cSId}->{'cdcSymptomName'} // die;
                my %o = ();
                $o{'cdcSymptomId'}   = $cSId;
                $o{'cdcSymptomName'} = $cdcSymptomName;
                push @{$obj{'symptoms'}}, \%o;
            }

            # Integrating vaccines details.
            my $cRVTb = $self->dbh->selectall_hashref("SELECT cdcVaccineId, dose FROM cdc_report_vaccine WHERE cdcReportId = $cdcReportId", 'cdcVaccineId') or die $!;
            for my $cVId (sort{$a <=> $b} keys %$cRVTb) {
                my $cdcVaccineName      = $cdcVaccines{$cVId}->{'cdcVaccineName'}      // die;
                my $cMId                = $cdcVaccines{$cVId}->{'cdcManufacturerId'}   // die;
                my $cdcManufacturerName = $cdcVaccines{$cVId}->{'cdcManufacturerName'} // die;
                my $cVTId               = $cdcVaccines{$cVId}->{'cdcVaccineTypeId'}    // die;
                my $cdcVaccineTypeName  = $cdcVaccines{$cVId}->{'cdcVaccineTypeName'}  // die;
                my $dose                = %$cRVTb{$cVId}->{'dose'}                     // '';
                my %o                   = ();
                $o{'cdcVaccineId'}      = $cVId;
                $o{'cdcVaccineName'}    = $cdcVaccineName;
                push @{$obj{'vaccines'}}, \%o;
                my %o2                     = ();
                $o2{'cdcManufacturerId'}   = $cMId;
                $o2{'cdcManufacturerName'} = $cdcManufacturerName;
                push @{$obj{'vaccineManufacturers'}}, \%o2;
                my %o3                     = ();
                $o3{'cdcVaccineTypeId'}    = $cVTId;
                $o3{'cdcVaccineTypeName'}  = $cdcVaccineTypeName;
                push @{$obj{'vaccineTypes'}}, \%o3;
                my %o4                     = ();
                $o4{'dose'}                = $dose;
                push @{$obj{'doses'}}, \%o4;
            }

            push @cdcReports, \%obj;
        }
    }
    my ($maxPages, %pages) = data_formatting::paginate($pageNumber, $totalEcdcReports, 50);
    # p%pages;
    # p@cdcReports;

    $self->render(
        pageNumber       => $pageNumber,
        maxPages         => $maxPages,
        totalEcdcReports => $totalEcdcReports,
        noticeSearch     => $noticeSearch,
        cdcReports      => \@cdcReports,
        pages            => \%pages
    );
}

1;