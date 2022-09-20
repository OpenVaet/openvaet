package OpenVaet::Controller::WizardBreastMilkExposureConfirmation;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

my $breastMilkExposuresData     = 'Exposure Via Breast Milk';
my %breastMilkExposuresSymptoms = ();
my %breastMilkExposuresKeywords = ();

sub wizard_breast_milk_exposure_confirmation {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching current batch.
    my $operationsToPerform = operations_to_perform($self);
    say "operationsToPerform: $operationsToPerform";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        operationsToPerform => $operationsToPerform,
        languages => \%languages
    );
}

sub operations_to_perform {
    my $self = shift;
    my $operationsToPerform = 0;
    my $wTb1 = $self->dbh->selectrow_hashref("SELECT count(id) as currentWizardTasks FROM breast_milk_wizard_report WHERE breastMilkExposureConfirmationRequired = 1 AND breastMilkExposureConfirmation IS NULL", undef);
    my $wTb2 = $self->dbh->selectrow_hashref("SELECT count(id) as totalWizardTasks   FROM breast_milk_wizard_report WHERE breastMilkExposureConfirmationRequired = 1", undef);
    my $currentWizardTasks  = %$wTb1{'currentWizardTasks'} // 0;
    my $totalWizardTasks    = %$wTb2{'totalWizardTasks'}   // 0;
    say "currentWizardTasks : $currentWizardTasks";
    say "totalWizardTasks   : $totalWizardTasks";
    if (!$totalWizardTasks) {
        $operationsToPerform = generate_batch($self);
        say "operationsToPerform   : $operationsToPerform";
    } else {
        if ($totalWizardTasks && $currentWizardTasks != 0) {
            # Nothing to do but to load the current sequence.
            $operationsToPerform = $currentWizardTasks;
        } else {

            # Truncating breast_milk_wizard_report table.
            my $sth = $self->dbh->prepare("TRUNCATE breast_milk_wizard_report");
            $sth->execute() or die $sth->err();

            $operationsToPerform = generate_batch($self);
        }
    }
}

sub generate_batch {
    my $self = shift;
    # Fetching total operations to perform.
    my $treatmentLimit = 100;
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE breastMilkExposureConfirmationRequired = 1 AND breastMilkExposureConfirmation IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql                 = "
            SELECT
                id as reportId,
                breastMilkExposureConfirmation,
                breastMilkExposureConfirmationRequired,
                breastMilkExposureConfirmationTimestamp
            FROM report
            WHERE 
                breastMilkExposureConfirmationRequired = 1 AND
                breastMilkExposureConfirmation IS NULL
            ORDER BY RAND()
            LIMIT $treatmentLimit";
        say "$sql";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $breastMilkExposureConfirmationRequired       = %$rTb{$reportId}->{'breastMilkExposureConfirmationRequired'} // die;
            $breastMilkExposureConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmationRequired, -32)));
            my $breastMilkExposureConfirmation               = %$rTb{$reportId}->{'breastMilkExposureConfirmation'};
            # $breastMilkExposureConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmation, -32)));
            my $breastMilkExposureConfirmationTimestamp      = %$rTb{$reportId}->{'breastMilkExposureConfirmationTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO breast_milk_wizard_report (reportId, breastMilkExposureConfirmationRequired, breastMilkExposureConfirmation, breastMilkExposureConfirmationTimestamp) VALUES (?, $breastMilkExposureConfirmationRequired, NULL, ?)");
            $sth->execute($reportId, $breastMilkExposureConfirmationTimestamp) or die $sth->err();
            $currentBatch++;
        }
        $operationsToPerform = $currentBatch;
    }
    return $operationsToPerform;
}

sub load_next_report {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);
    my %enums = %{$self->enums()};

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // die;
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
    }

    load_breast_milk_exposures_symptoms($self);
    load_breast_milk_exposures_keywords($self);

    # Fetching confirmation target.
    # Fetching total operations to perform.
    my $operationsToPerform = operations_to_perform($self);

    my ($hospitalized, $permanentDisability, $lifeThreatning, $patientDied, $reportId,
        $vaersId, $symptoms, $vaccinesListed, $vaersReceptionDate, $vaccinationDate,
        $vaccinationDateFixed, $vaccinationYear, $vaccinationMonth, $vaccinationDay, $onsetDate,
        $onsetDateFixed, $onsetYear, $onsetMonth, $onsetDay, $products,
        $deceasedYear, $deceasedMonth, $deceasedDay, $deceasedDate, $sexFixed,
        $vaersSexName, $aEDescription, $patientAgeFixed, $creationDatetime, $hoursBetweenVaccineAndAE,
        $breastMilkExposureConfirmation, $breastMilkExposureConfirmationRequired);
    my $sqlParam            = 'breastMilkExposureConfirmationRequired';
    my $sqlValue            = 'breastMilkExposureConfirmation';
    if ($operationsToPerform) {
        my $sql                 = "
            SELECT
                breast_milk_wizard_report.reportId,
                report.vaersId,
                report.vaccinesListed,
                report.sexFixed,
                report.patientAgeFixed,
                report.creationTimestamp,
                report.aEDescription,
                report.vaersReceptionDate,
                report.onsetDate,
                report.deceasedDate,
                report.vaccinationDateFixed,
                report.onsetDateFixed,
                report.vaccinationDate,
                report.vaccinesListed,
                report.breastMilkExposureConfirmation,
                report.breastMilkExposureConfirmationRequired,
                report.hoursBetweenVaccineAndAE,
                report.hospitalized,
                report.permanentDisability,
                report.lifeThreatning,
                report.patientDied,
                report.symptomsListed
            FROM breast_milk_wizard_report
                LEFT JOIN report ON report.id = breast_milk_wizard_report.reportId
            WHERE 
                breast_milk_wizard_report.$sqlParam = 1 AND
                breast_milk_wizard_report.$sqlValue IS NULL
            ORDER BY RAND()
            LIMIT 1";
        say "$sql";
        my $rTb                 = $self->dbh->selectrow_hashref($sql, undef); # ORDER BY RAND()
        $reportId                             = %$rTb{'reportId'}                        // die;
        $vaersId                              = %$rTb{'vaersId'}                         // die;
        $vaccinesListed                       = %$rTb{'vaccinesListed'}                  // die;
        $sexFixed                             = %$rTb{'sexFixed'}                        // die;
        $vaersSexName                         = $enums{'vaersSex'}->{$sexFixed}          // die;
        $patientAgeFixed                      = %$rTb{'patientAgeFixed'};
        $hoursBetweenVaccineAndAE             = %$rTb{'hoursBetweenVaccineAndAE'};
        my $creationTimestamp                 = %$rTb{'creationTimestamp'}               // die;
        $creationDatetime                     = time::timestamp_to_datetime($creationTimestamp);
        $aEDescription                        = %$rTb{'aEDescription'}                   // die;
        $vaersReceptionDate                   = %$rTb{'vaersReceptionDate'}              // die;
        $breastMilkExposureConfirmationRequired = %$rTb{'breastMilkExposureConfirmationRequired'} // die;
        $breastMilkExposureConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmationRequired, -32)));
        $hospitalized                         = %$rTb{'hospitalized'}        // die;
        $hospitalized                            = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
        $permanentDisability                  = %$rTb{'permanentDisability'} // die;
        $permanentDisability                     = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
        $lifeThreatning                       = %$rTb{'lifeThreatning'}      // die;
        $lifeThreatning                          = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
        $patientDied                          = %$rTb{'patientDied'}         // die;
        $patientDied                             = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
        $vaccinationDate                      = %$rTb{'vaccinationDate'};
        $onsetDate                            = %$rTb{'onsetDate'};
        $vaccinationDateFixed                 = %$rTb{'vaccinationDateFixed'};
        $onsetDateFixed                       = %$rTb{'onsetDateFixed'};
        $breastMilkExposureConfirmation         = %$rTb{'breastMilkExposureConfirmation'};
        $deceasedDate                              = %$rTb{'deceasedDate'};
        if ($deceasedDate) {
            ($deceasedYear, $deceasedMonth, $deceasedDay) = split '-', $deceasedDate;
        }
        $vaccinesListed = decode_json($vaccinesListed);
        for my $vaccineData (@$vaccinesListed) {
            my $substanceShortenedName = %$vaccineData{'substanceShortenedName'} // die;
            my $dose = %$vaccineData{'dose'} // die;
            $products .= "<li><span>$substanceShortenedName (dose $dose)</span></li>";
        }

        for my $hl (sort keys %breastMilkExposuresKeywords) {
            my $ucf = ucfirst $hl;
            my $uc = uc $hl;
            $aEDescription =~ s/$hl/\<span style=\"background:yellow;\"\>$hl\<\/span\>/g;
            $aEDescription =~ s/$ucf/\<span style=\"background:yellow;\"\>$ucf\<\/span\>/g;
            $aEDescription =~ s/$uc/\<span style=\"background:yellow;\"\>$uc\<\/span\>/g;
        }
        my $symptomsListed                = %$rTb{'symptomsListed'}  // die;
        $symptomsListed                   = decode_json($symptomsListed);
        $symptoms = '<div style="width:300px;margin:auto;"><ul>';
        for my $symptomId (@$symptomsListed) {
            my $symptomName = $symptoms{$symptomId}->{'symptomName'} // die;
            if (exists $breastMilkExposuresSymptoms{$symptomId}) {
                $symptoms .= '<li><span style="background:yellow;">' . $symptomName . '</span></li>';
            } else {
                $symptoms .= '<li><span>' . $symptomName . '</span></li>';
            }
        }
        $symptoms .= '</ul></div>';
        if ($vaccinationDateFixed) {
            ($vaccinationYear, $vaccinationMonth, $vaccinationDay) = split '-', $vaccinationDateFixed;
        }
        if ($onsetDateFixed) {
            ($onsetYear, $onsetMonth, $onsetDay) = split '-', $onsetDateFixed;
        }
    }

    my %sexes = ();
    $sexes{'1'}->{'sexName'} = 'Female';
    $sexes{'2'}->{'sexName'} = 'Male';
    $sexes{'3'}->{'sexName'} = 'Unknown';

    say "reportId : $reportId";

    $self->render(
        currentLanguage                => $currentLanguage,
        sqlValue                       => $sqlValue,
        operationsToPerform            => $operationsToPerform,
        hospitalized                   => $hospitalized,
        permanentDisability            => $permanentDisability,
        lifeThreatning                 => $lifeThreatning,
        patientDied                    => $patientDied,
        reportId                       => $reportId,
        vaersId                        => $vaersId,
        symptoms                       => $symptoms,
        vaccinesListed                 => $vaccinesListed,
        vaersReceptionDate             => $vaersReceptionDate,
        vaccinationDate                => $vaccinationDate,
        vaccinationDateFixed           => $vaccinationDateFixed,
        vaccinationYear                => $vaccinationYear,
        vaccinationMonth               => $vaccinationMonth,
        vaccinationDay                 => $vaccinationDay,
        onsetDate                      => $onsetDate,
        onsetDateFixed                 => $onsetDateFixed,
        onsetYear                      => $onsetYear,
        onsetMonth                     => $onsetMonth,
        onsetDay                       => $onsetDay,
        products                       => $products,
        deceasedYear                   => $deceasedYear,
        deceasedMonth                  => $deceasedMonth,
        deceasedDay                    => $deceasedDay,
        deceasedDate                   => $deceasedDate,
        sexFixed                  => $sexFixed,
        vaersSexName                   => $vaersSexName,
        aEDescription                  => $aEDescription,
        patientAgeFixed                => $patientAgeFixed,
        creationDatetime               => $creationDatetime,
        hoursBetweenVaccineAndAE       => $hoursBetweenVaccineAndAE,
        breastMilkExposureConfirmation         => $breastMilkExposureConfirmation,
        breastMilkExposureConfirmationRequired => $breastMilkExposureConfirmationRequired,
        sexes                          => \%sexes,
        languages                      => \%languages
    );
}

sub load_breast_milk_exposures_symptoms {
    my $self = shift;
    my $breastMilkExposuresSymptomsSetId = get_breast_milk_exposures_symptoms_set($self);
    my $tb = $self->dbh->selectrow_hashref("SELECT symptoms FROM symptoms_set WHERE id = $breastMilkExposuresSymptomsSetId", undef);
    die unless keys %$tb;
    my $symptoms = %$tb{'symptoms'} // die;
    $symptoms = decode_json($symptoms);
    for my $symptomId (@$symptoms) {
        $breastMilkExposuresSymptoms{$symptomId} = 1;
    }
}

sub load_breast_milk_exposures_keywords {
    my $self = shift;
    my $breastMilkExposuresKeywordsSetId = get_breast_milk_exposures_keywords_set($self);
    my $tb = $self->dbh->selectrow_hashref("SELECT keywords FROM keywords_set WHERE id = $breastMilkExposuresKeywordsSetId", undef);
    die unless keys %$tb;
    my $keywords = %$tb{'keywords'} // die;
    my @keywordsFiltered = split '<br \/>', $keywords;
    for my $keyword (@keywordsFiltered) {
        my $lcKeyword = lc $keyword;
        $breastMilkExposuresKeywords{$lcKeyword} = 1;
    }
}

sub get_breast_milk_exposures_symptoms_set {
    my $self = shift;
    my $tb = $self->dbh->selectrow_hashref("SELECT id as symptomsSetId FROM symptoms_set WHERE name = ?", undef, $breastMilkExposuresData);
    die unless keys %$tb;
    return %$tb{'symptomsSetId'};
}

sub get_breast_milk_exposures_keywords_set {
    my $self = shift;
    my $tb = $self->dbh->selectrow_hashref("SELECT id as keywordsSetId FROM keywords_set WHERE name = ?", undef, $breastMilkExposuresData);
    die unless keys %$tb;
    return %$tb{'keywordsSetId'};
}

sub set_report_attribute {
    my $self              = shift;
    my $reportId          = $self->param('reportId')        // die;
    my $sqlValue          = $self->param('sqlValue')        // die;
    my $value             = $self->param('value')           // die;
    my $userId            = $self->session('userId')        // die;
    my $patientAgeFixed   = $self->param('patientAgeFixed') // die;
    $patientAgeFixed      = undef unless length $patientAgeFixed    >= 1;
    my $sexFixed     = $self->param('sexFixed')   // die;
    my $vaccinationYear   = $self->param('vaccinationYear') // die;
    $vaccinationYear      = undef unless length $vaccinationYear    >= 1;
    my $vaccinationMonth   = $self->param('vaccinationMonth') // die;
    $vaccinationMonth      = undef unless length $vaccinationMonth    >= 1;
    my $vaccinationDay   = $self->param('vaccinationDay') // die;
    $vaccinationDay      = undef unless length $vaccinationDay    >= 1;
    my $deceasedYear   = $self->param('deceasedYear') // die;
    $deceasedYear      = undef unless length $deceasedYear    >= 1;
    my $deceasedMonth   = $self->param('deceasedMonth') // die;
    $deceasedMonth      = undef unless length $deceasedMonth    >= 1;
    my $deceasedDay   = $self->param('deceasedDay') // die;
    $deceasedDay      = undef unless length $deceasedDay    >= 1;
    my $onsetYear   = $self->param('onsetYear') // die;
    $onsetYear      = undef unless length $onsetYear    >= 1;
    my $onsetMonth   = $self->param('onsetMonth') // die;
    $onsetMonth      = undef unless length $onsetMonth    >= 1;
    my $onsetDay   = $self->param('onsetDay') // die;
    $onsetDay      = undef unless length $onsetDay    >= 1;
    my ($onsetDateFixed, $vaccinationDateFixed, $deceasedDateFixed);
    if ($vaccinationYear && $vaccinationMonth && $vaccinationDay) {
        $vaccinationDateFixed = "$vaccinationYear-$vaccinationMonth-$vaccinationDay";
    }
    if ($onsetYear && $onsetMonth && $onsetDay) {
        $onsetDateFixed = "$onsetYear-$onsetMonth-$onsetDay";
    }
    if ($deceasedYear && $deceasedMonth && $deceasedDay) {
        $deceasedDateFixed = "$deceasedYear-$deceasedMonth-$deceasedDay";
    }
    my $patientDied   = $self->param('patientDied') // die;
    my $lifeThreatning   = $self->param('lifeThreatning') // die;
    my $permanentDisability   = $self->param('permanentDisability') // die;
    my $hospitalized   = $self->param('hospitalized') // die;
    my $hoursBetweenVaccineAndAE   = $self->param('hoursBetweenVaccineAndAE') // die;
    $hoursBetweenVaccineAndAE      = undef unless length $hoursBetweenVaccineAndAE    >= 1;
    if ($onsetDateFixed && $vaccinationDateFixed && !defined $hoursBetweenVaccineAndAE) {
        $hoursBetweenVaccineAndAE = time::calculate_minutes_difference("$vaccinationDateFixed 12:00:00", "$onsetDateFixed 12:00:00");
        $hoursBetweenVaccineAndAE = nearest(0.01, ($hoursBetweenVaccineAndAE / 60));
    }
    my $sth = $self->dbh->prepare("
        UPDATE report SET
            $sqlValue = $value,
            patientAgeFixed = ?,
            sexFixed = ?,
            vaccinationDateFixed = ?,
            onsetDateFixed = ?,
            deceasedDateFixed = ?,
            hoursBetweenVaccineAndAE = ?,
            patientDiedFixed = $patientDied,
            lifeThreatningFixed = $lifeThreatning,
            permanentDisabilityFixed = $permanentDisability,
            hospitalizedFixed = $hospitalized,
            breastMilkExposureConfirmationTimestamp = UNIX_TIMESTAMP(),
            breastMilkExposureConfirmationUserId = ?
        WHERE id = $reportId");
    $sth->execute(
        $patientAgeFixed,
        $sexFixed,
        $vaccinationDateFixed,
        $onsetDateFixed,
        $deceasedDateFixed,
        $hoursBetweenVaccineAndAE,
        $userId
    ) or die $sth->err();
    my $sth2 = $self->dbh->prepare("
        UPDATE breast_milk_wizard_report SET
            $sqlValue = $value,
            breastMilkExposureConfirmationTimestamp = UNIX_TIMESTAMP()
        WHERE reportId = $reportId");
    $sth2->execute(
    ) or die $sth2->err();

    say "reportId : $reportId";

    $self->render(text => 'ok');
}

sub breast_milk_exposure_confirmation_completed {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $adminFilter     = $self->param('adminFilter');
    my $productFilter   = $self->param('productFilter');
    say "productFilter : $productFilter";

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my %reports = ();
    my ($breastMilkExposuresConfirmed, $totalReports) = (0, 0);
    my %admins = ();
    my %products = ();
    my $tb = $self->dbh->selectall_hashref("
        SELECT
            report.id as reportId,
            report.breastMilkExposureConfirmation,
            report.vaersId,
            report.vaccinesListed,
            report.breastMilkExposureConfirmationTimestamp,
            report.breastMilkExposureConfirmationUserId,
            user.email 
        FROM report
            LEFT JOIN user ON user.id = report.breastMilkExposureConfirmationUserId
        WHERE breastMilkExposureConfirmationTimestamp IS NOT NULL
    ", 'reportId');
    for my $reportId (sort{$a <=> $b} keys %$tb) {
        my $breastMilkExposureConfirmation = %$tb{$reportId}->{'breastMilkExposureConfirmation'} // die;
        $breastMilkExposureConfirmation    = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmation, -32)));
        my $breastMilkExposureConfirmationTimestamp = %$tb{$reportId}->{'breastMilkExposureConfirmationTimestamp'} // die;
        my $breastMilkExposureConfirmationDatetime  = time::timestamp_to_datetime($breastMilkExposureConfirmationTimestamp);
        my $breastMilkExposureConfirmationUserId                          = %$tb{$reportId}->{'breastMilkExposureConfirmationUserId'}                          // die;
        my $vaersId                         = %$tb{$reportId}->{'vaersId'}                         // die;
        my $email                           = %$tb{$reportId}->{'email'}                           // die;
        my ($userName) = split '\@', $email;
        $admins{$userName} = 1;
        if ($adminFilter) {
            next if $userName ne $adminFilter;
        }
        my $vaccinesListed                  = %$tb{$reportId}->{'vaccinesListed'}                  // die;
        $vaccinesListed = decode_json($vaccinesListed);
        my %vax = ();
        my $hasProduct = 0;
        for my $vaccineData (@$vaccinesListed) {
            my $substanceShortenedName = %$vaccineData{'substanceShortenedName'} // die;
            if ($productFilter) {
                $hasProduct = 1 if $substanceShortenedName eq $productFilter;
            }
            $vax{$substanceShortenedName} = 1;
            $products{$substanceShortenedName} = 1;
        }
        if ($productFilter) {
            next unless $hasProduct;
        }
        $breastMilkExposuresConfirmed++ if $breastMilkExposureConfirmation;
        $totalReports++;
        for my $substanceShortenedName (sort keys %vax) {
            $reports{$breastMilkExposureConfirmationTimestamp}->{$reportId}->{'products'}->{$substanceShortenedName} = 1;
        }
        $reports{$breastMilkExposureConfirmationTimestamp}->{$reportId}->{'breastMilkExposureConfirmationDatetime'} = $breastMilkExposureConfirmationDatetime;
        $reports{$breastMilkExposureConfirmationTimestamp}->{$reportId}->{'breastMilkExposureConfirmation'} = $breastMilkExposureConfirmation;
        $reports{$breastMilkExposureConfirmationTimestamp}->{$reportId}->{'userName'} = $userName;
        $reports{$breastMilkExposureConfirmationTimestamp}->{$reportId}->{'vaersId'} = $vaersId;
    }
    my $breastMilkExposuresConfirmedPercent = 0;
    if ($totalReports) {
        $breastMilkExposuresConfirmedPercent = nearest(0.01, $breastMilkExposuresConfirmed * 100 / $totalReports);
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        adminFilter => $adminFilter,
        productFilter => $productFilter,
        breastMilkExposuresConfirmed => $breastMilkExposuresConfirmed,
        totalReports => $totalReports,
        breastMilkExposuresConfirmedPercent => $breastMilkExposuresConfirmedPercent,
        admins => \%admins,
        products => \%products,
        languages => \%languages,
        reports => \%reports
    );
}

sub reset_report_attributes {
    my $self = shift;
    my $reportId = $self->param('reportId') // die;

    say "reportId : $reportId";
    my $sth = $self->dbh->prepare("UPDATE report SET breastMilkExposureConfirmation = NULL, breastMilkExposureConfirmationTimestamp = NULL, breastMilkExposureConfirmationUserId = NULL WHERE id = $reportId");
    $sth->execute() or die $sth->err();

    $self->render(text => 'ok');
}

1;