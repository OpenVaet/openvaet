package OpenVaet::Controller::WizardPatientAge;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub wizard_patient_age {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching current batch.
    my $operationsToPerform = operations_to_perform($self);

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
    my $wTb1 = $self->dbh->selectrow_hashref("SELECT count(id) as currentWizardTasks FROM age_wizard_report WHERE patientAgeConfirmationRequired = 1 AND patientAgeConfirmation IS NULL", undef);
    my $wTb2 = $self->dbh->selectrow_hashref("SELECT count(id) as totalWizardTasks   FROM age_wizard_report WHERE patientAgeConfirmationRequired = 1", undef);
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

            # Truncating age_wizard_report table.
            my $sth = $self->dbh->prepare("TRUNCATE age_wizard_report");
            $sth->execute() or die $sth->err();

            $operationsToPerform = generate_batch($self);
        }
    }
    return $operationsToPerform;
}

sub generate_batch {
    my $self = shift;
    # Fetching total operations to perform.
    my $treatmentLimit = 100;
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE patientAgeConfirmationRequired = 1 AND patientAgeConfirmation IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql                 = "
            SELECT
                id as reportId,
                patientAgeConfirmation,
                patientAgeConfirmationRequired,
                patientAgeConfirmationTimestamp
            FROM report
            WHERE 
                patientAgeConfirmationRequired = 1 AND
                patientAgeConfirmation IS NULL
            ORDER BY RAND()
            LIMIT $treatmentLimit";
        say "$sql";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $patientAgeConfirmationRequired       = %$rTb{$reportId}->{'patientAgeConfirmationRequired'} // die;
            $patientAgeConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
            my $patientAgeConfirmation               = %$rTb{$reportId}->{'patientAgeConfirmation'};
            # $patientAgeConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmation, -32)));
            my $patientAgeConfirmationTimestamp      = %$rTb{$reportId}->{'patientAgeConfirmationTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO age_wizard_report (reportId, patientAgeConfirmationRequired, patientAgeConfirmation, patientAgeConfirmationTimestamp) VALUES (?, $patientAgeConfirmationRequired, NULL, ?)");
            $sth->execute($reportId, $patientAgeConfirmationTimestamp) or die $sth->err();
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

    # Fetching confirmation target.
    # Fetching total operations to perform.
    my $operationsToPerform = operations_to_perform($self);

    my ($hospitalized, $permanentDisability, $lifeThreatning, $patientDied, $reportId,
        $vaersId, $symptoms, $vaccinesListed, $vaersReceptionDate, $vaccinationDate,
        $vaccinationDateFixed, $vaccinationYear, $vaccinationMonth, $vaccinationDay, $onsetDate,
        $onsetDateFixed, $onsetYear, $onsetMonth, $onsetDay, $products,
        $deceasedYear, $deceasedMonth, $deceasedDay, $deceasedDate, $sexFixed,
        $vaersSexName, $aEDescription, $patientAgeFixed, $creationDatetime, $hoursBetweenVaccineAndAE,
        $patientAgeConfirmation, $patientAgeConfirmationRequired);
    my $sqlParam            = 'patientAgeConfirmationRequired';
    my $sqlValue            = 'patientAgeConfirmation';
    if ($operationsToPerform) {
        my $sql                 = "
            SELECT
                age_wizard_report.reportId,
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
                report.patientAgeConfirmation,
                report.patientAgeConfirmationRequired,
                report.hoursBetweenVaccineAndAE,
                report.hospitalized,
                report.permanentDisability,
                report.lifeThreatning,
                report.patientDied,
                report.symptomsListed
            FROM age_wizard_report
                LEFT JOIN report ON report.id = age_wizard_report.reportId
            WHERE 
                age_wizard_report.$sqlParam = 1 AND
                age_wizard_report.$sqlValue IS NULL
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
        $patientAgeConfirmationRequired = %$rTb{'patientAgeConfirmationRequired'} // die;
        $patientAgeConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
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
        $patientAgeConfirmation         = %$rTb{'patientAgeConfirmation'};
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

        my @highlights = ('age', 'year', 'deceased', 'yo', 'week', 'day', 'old', 'decade');
        for my $hl (@highlights) {
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
            $symptoms .= '<li><span>' . $symptomName . '</span></li>';
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
        patientAgeConfirmation         => $patientAgeConfirmation,
        patientAgeConfirmationRequired => $patientAgeConfirmationRequired,
        sexes                          => \%sexes,
        languages                      => \%languages
    );
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
            patientAgeConfirmationTimestamp = UNIX_TIMESTAMP(),
            patientAgeUserId = ?
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
        UPDATE age_wizard_report SET
            $sqlValue = $value,
            patientAgeConfirmationTimestamp = UNIX_TIMESTAMP()
        WHERE reportId = $reportId");
    $sth2->execute(
    ) or die $sth2->err();

    say "reportId : $reportId";

    $self->render(text => 'ok');
}

sub patient_ages_completed {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $adminFilter     = $self->param('adminFilter');
    my $productFilter   = $self->param('productFilter');
    say "productFilter : $productFilter";

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my %reports = ();
    my ($agesCompleted, $totalReports) = (0, 0);
    my %admins = ();
    my %products = ();
    my $tb = $self->dbh->selectall_hashref("
        SELECT
            report.id as reportId,
            report.patientAgeFixed,
            report.vaersId,
            report.vaccinesListed,
            report.patientAgeConfirmationTimestamp,
            report.patientAgeUserId,
            user.email 
        FROM report
            LEFT JOIN user ON user.id = report.patientAgeUserId
        WHERE patientAgeConfirmationTimestamp IS NOT NULL
    ", 'reportId');
    for my $reportId (sort{$a <=> $b} keys %$tb) {
        my $patientAgeFixed                 = %$tb{$reportId}->{'patientAgeFixed'};
        my $patientAgeConfirmationTimestamp = %$tb{$reportId}->{'patientAgeConfirmationTimestamp'} // die;
        my $patientAgeConfirmationDatetime  = time::timestamp_to_datetime($patientAgeConfirmationTimestamp);
        my $patientAgeUserId                          = %$tb{$reportId}->{'patientAgeUserId'}                          // die;
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
        $agesCompleted++ if defined $patientAgeFixed;
        $totalReports++;
        for my $substanceShortenedName (sort keys %vax) {
            $reports{$patientAgeConfirmationTimestamp}->{$reportId}->{'products'}->{$substanceShortenedName} = 1;
        }
        $reports{$patientAgeConfirmationTimestamp}->{$reportId}->{'patientAgeConfirmationDatetime'} = $patientAgeConfirmationDatetime;
        $reports{$patientAgeConfirmationTimestamp}->{$reportId}->{'patientAgeFixed'} = $patientAgeFixed;
        $reports{$patientAgeConfirmationTimestamp}->{$reportId}->{'userName'} = $userName;
        $reports{$patientAgeConfirmationTimestamp}->{$reportId}->{'vaersId'} = $vaersId;
    }
    my $agesCompletedPercent = 0;
    if ($totalReports) {
        $agesCompletedPercent = nearest(0.01, $agesCompleted * 100 / $totalReports);
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        adminFilter => $adminFilter,
        productFilter => $productFilter,
        agesCompleted => $agesCompleted,
        totalReports => $totalReports,
        agesCompletedPercent => $agesCompletedPercent,
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
    my $sth = $self->dbh->prepare("UPDATE report SET patientAgeConfirmation = NULL, patientAgeConfirmationTimestamp = NULL, patientAgeUserId = NULL WHERE id = $reportId");
    $sth->execute() or die $sth->err();

    $self->render(text => 'ok');
}

sub patient_ages_custom_export {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my %admins = ();
    my $tb = $self->dbh->selectall_hashref("
        SELECT
            DISTINCT(user.email) 
        FROM report
            LEFT JOIN user ON user.id = report.patientAgeUserId
        WHERE patientAgeConfirmationTimestamp IS NOT NULL
    ", 'email');
    for my $email (sort keys %$tb) {
        my ($userName) = split '\@', $email;
        $admins{$userName} = 1;
    }

    # Fetching symptoms sets.
    my %symptomsSets = ();
    my $sTb = $self->dbh->selectall_hashref("
        SELECT
            symptoms_set.id as symptomSetId,
            symptoms_set.name as symptomSetName,
            user.email
        FROM symptoms_set
            LEFT JOIN user ON user.id = symptoms_set.userId
        ", 'symptomSetId');
    for my $symptomsSetId (sort{$a <=> $b} keys %$sTb) {
        my $symptomSetName = %$sTb{$symptomsSetId}->{'symptomSetName'} // die;
        my $email = %$sTb{$symptomsSetId}->{'email'} // die;
        my ($userName) = split '\@', $email;
        $symptomsSets{"$userName - $symptomSetName"}->{'symptomsSetId'} = $symptomsSetId;
    }

    # Fetching keywords sets.
    my %keywordsSets = ();
    my $kTb = $self->dbh->selectall_hashref("
        SELECT
            keywords_set.id as symptomSetId,
            keywords_set.name as symptomSetName,
            user.email
        FROM keywords_set
            LEFT JOIN user ON user.id = keywords_set.userId
        ", 'symptomSetId');
    for my $keywordsSetId (sort{$a <=> $b} keys %$kTb) {
        my $symptomSetName = %$kTb{$keywordsSetId}->{'symptomSetName'} // die;
        my $email = %$kTb{$keywordsSetId}->{'email'} // die;
        my ($userName) = split '\@', $email;
        $keywordsSets{"$userName - $symptomSetName"}->{'keywordsSetId'} = $keywordsSetId;
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my %products = ();
    $products{'COVID-19 VACCINE JANSSEN'}                  = 'janssen';
    $products{'COVID-19 VACCINE MODERNA'}                  = 'moderna';
    $products{'COVID-19 VACCINE MODERNA BIVALENT'}         = 'modernaBivalent';
    $products{'COVID-19 VACCINE NOVAVAX'}                  = 'novavax';
    $products{'COVID-19 VACCINE PFIZER-BIONTECH'}          = 'pfizer';
    $products{'COVID-19 VACCINE PFIZER-BIONTECH BIVALENT'} = 'pfizerBivalent';
    $products{'COVID-19 VACCINE UNKNOWN MANUFACTURER'}     = 'unknown';

    my %severities = ();
    $severities{'1'}->{'label'} = 'Died';
    $severities{'1'}->{'value'} = 'patientDiedFixed';
    $severities{'2'}->{'label'} = 'Permanent Disability';
    $severities{'2'}->{'value'} = 'permanentDisabilityFixed';
    $severities{'3'}->{'label'} = 'Life Threatening';
    $severities{'3'}->{'value'} = 'lifeThreatningFixed';
    $severities{'4'}->{'label'} = 'Hospitalized';
    $severities{'4'}->{'value'} = 'hospitalizedFixed';

    $self->render(
        currentLanguage => $currentLanguage,
        products => \%products,
        languages => \%languages,
        symptomsSets => \%symptomsSets,
        keywordsSets => \%keywordsSets,
        severities => \%severities,
        admins => \%admins
    );
}

sub admin_custom_export {
    my $self   = shift;
    my $userId = $self->session('userId') // die;

    my $reports;
    open my $in, '<:utf8', "public/admin_exports/export_$userId.json";
    while (<$in>) {
        $reports .= $_;
    }
    close $in;
    $reports = decode_json($reports);
    my %reports = %$reports;


    $self->render(
        reports  => \%reports
    );
}

sub generate_products_export {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;

    my %enums = %{$self->enums()};

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';
    my $params = $self->req->params->names;
    p$params;

    my $userId                 = $self->session('userId')               // die;
    my $janssen                = $self->param('janssen')                // die;
    my $moderna                = $self->param('moderna')                // die;
    my $pfizer                 = $self->param('pfizer')                 // die;
    my $novavax                = $self->param('novavax')                // die;
    my $unknown                = $self->param('unknown')                // die;
    my $adminFilter            = $self->param('adminFilter')            // die;
    my $symptomFilter          = $self->param('symptomFilter')          // die;
    my $keywordsFilter         = $self->param('keywordsFilter')         // die;
    my $severityFilter         = $self->param('severityFilter')         // die;
    my $ageErrorsOnly          = $self->param('ageErrorsOnly')          // die;
    my $ageCompletedOnly       = $self->param('ageCompletedOnly')       // die;
    my $pregnanciesOnly        = $self->param('pregnanciesOnly')        // die;
    my $breastMilkExposureOnly = $self->param('breastMilkExposureOnly') // die;
    my $modernaBivalent        = $self->param('modernaBivalent')        // die;
    my $pfizerBivalent         = $self->param('pfizerBivalent')         // die;
    say "ageErrorsOnly          : $ageErrorsOnly";
    say "ageCompletedOnly       : $ageCompletedOnly";
    say "pregnanciesOnly        : $pregnanciesOnly";
    say "breastMilkExposureOnly : $breastMilkExposureOnly";
    say "symptomFilter          : $symptomFilter";
    say "keywordsFilter         : $keywordsFilter";

    # Fetching symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
    }

    # If filtered by a set of symptoms, fetching them.
    my %symptomsFiltered = ();
    if ($symptomFilter) {
        my $sTb = $self->dbh->selectrow_hashref("SELECT symptoms FROM symptoms_set WHERE id = $symptomFilter", undef);
        my $symptomsFiltered = %$sTb{'symptoms'} // die;
        $symptomsFiltered = decode_json($symptomsFiltered);
        for my $symptomId (@$symptomsFiltered) {
            die unless exists $symptoms{$symptomId}->{'symptomName'};
            $symptomsFiltered{$symptomId} = 1;
        }
        $symptomFilter    = undef unless keys %symptomsFiltered;
    }

    # If filtered by keywords, fetching them.
    my %keywordsFiltered = ();
    if ($keywordsFilter) {
        my $sTb = $self->dbh->selectrow_hashref("SELECT keywords FROM keywords_set WHERE id = $keywordsFilter", undef);
        my $keywordsFiltered = %$sTb{'keywords'} // die;
        my @keywordsFiltered = split '<br \/>', $keywordsFiltered;
        for my $keyword (@keywordsFiltered) {
            my $lcKeyword = lc $keyword;
            $keywordsFiltered{$lcKeyword} = 1;
        }
        $keywordsFilter    = undef unless keys %keywordsFiltered;
    }


    # Listing products we look for.
    my %products = ();
    $products{'janssen'}->{'name'} = 'COVID-19 VACCINE JANSSEN';
    $products{'janssen'}->{'status'} = $janssen;
    $products{'moderna'}->{'name'} = 'COVID-19 VACCINE MODERNA';
    $products{'moderna'}->{'status'} = $moderna;
    $products{'novavax'}->{'name'} = 'COVID-19 VACCINE NOVAVAX';
    $products{'novavax'}->{'status'} = $novavax;
    $products{'pfizer'}->{'name'}  = 'COVID-19 VACCINE PFIZER-BIONTECH';
    $products{'pfizer'}->{'status'} = $pfizer;
    $products{'pfizerBivalent'}->{'name'}  = 'COVID-19 VACCINE PFIZER-BIONTECH BIVALENT';
    $products{'pfizerBivalent'}->{'status'} = $pfizerBivalent;
    $products{'modernaBivalent'}->{'name'}  = 'COVID-19 VACCINE MODERNA BIVALENT';
    $products{'modernaBivalent'}->{'status'} = $modernaBivalent;
    $products{'unknown'}->{'name'} = 'COVID-19 VACCINE UNKNOWN MANUFACTURER';
    $products{'unknown'}->{'status'} = $unknown;
    my %productsSearched = ();
    for my $productLabel (sort keys %products) {
        my $name = $products{$productLabel}->{'name'} // die;
        my $status = $products{$productLabel}->{'status'} // die;
        if ($status eq 'true') {
            $productsSearched{$name} = 1;
        }
    }
    p%productsSearched;

    # Fetching all the reports corresponding to the selected manufacturer.
    my %reports = ();
    my $exported = 0;
    my $sql = "
        SELECT
            report.id as reportId,
            report.vaersId,
            report.vaccinesListed,
            report.aEDescription,
            report.vaersSource,
            report.sexFixed,
            report.countryStateId,
            report.countryId,
            country.name as countryName,
            country_state.name as countryStateName,
            report.onsetDateFixed,
            report.deceasedDateFixed,
            report.vaccinationDateFixed,
            report.vaersReceptionDate,
            report.patientAgeFixed,
            report.patientAge,
            report.symptomsListed,
            report.hospitalizedFixed,
            report.lifeThreatningFixed,
            report.permanentDisabilityFixed,
            report.patientDiedFixed,
            report.patientAgeConfirmationRequired,
            user.email 
        FROM report
            LEFT JOIN user ON user.id = report.patientAgeUserId
            LEFT JOIN country_state ON country_state.id = report.countryStateId
            LEFT JOIN country ON country.id = report.countryId
        ";
    my $hasConditional = 0;
    if ($severityFilter || $pregnanciesOnly eq 'true' || $breastMilkExposureOnly eq 'true') {
        $sql .= " WHERE ";
    }
    if ($severityFilter) {
        $hasConditional = 1;
        $sql .= " report.$severityFilter = 1";
    }
    if ($pregnanciesOnly eq 'true') {
        if ($hasConditional) {
            $sql .= " AND report.pregnancyConfirmation = 1";
        } else {
            $sql .= " report.pregnancyConfirmation = 1";
        }
        $hasConditional = 1;
    }
    if ($breastMilkExposureOnly eq 'true') {
        if ($hasConditional) {
            $sql .= " AND report.breastMilkExposureConfirmation = 1";
        } else {
            $sql .= " report.breastMilkExposureConfirmation = 1";
        }
        $hasConditional = 1;
    }
    say $sql;
    my $tb = $self->dbh->selectall_hashref($sql, 'reportId');
    for my $reportId (sort{$a <=> $b} keys %$tb) {
        my $vaccinesListed = %$tb{$reportId}->{'vaccinesListed'} // die;
        my $patientAgeFixed = %$tb{$reportId}->{'patientAgeFixed'};
        my $patientAgeConfirmationRequired = %$tb{$reportId}->{'patientAgeConfirmationRequired'} // die;
        $patientAgeConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
        if ($ageErrorsOnly eq 'true') {
            next if $patientAgeConfirmationRequired == 0;
        }
        if ($ageCompletedOnly eq 'true') {
            next unless defined $patientAgeFixed;
        }
        if ($adminFilter && ($adminFilter == 1)) {
            my $email = %$tb{$reportId}->{'email'} // next;
            my ($userName) = split '\@', $email;
            if ($adminFilter) {
                next if $userName ne $adminFilter;
            }
        }
        $vaccinesListed = decode_json($vaccinesListed);
        my $hasProduct  = 0;
        for my $vaccineData (@$vaccinesListed) {
            my $substanceShortenedName = %$vaccineData{'substanceShortenedName'} // die;
            if (exists $productsSearched{$substanceShortenedName}) {
                $hasProduct = 1;
                last;
            }
        }
        if ($hasProduct == 1) {
            my $vaersId = %$tb{$reportId}->{'vaersId'} // die;
            my $vaersReceptionDate = %$tb{$reportId}->{'vaersReceptionDate'} // die;
            my $aEDescription = %$tb{$reportId}->{'aEDescription'} // die;
            my $aEDescriptionNormalized = lc $aEDescription;
            my $immProjectNumber = %$tb{$reportId}->{'immProjectNumber'};
            my $countryName = %$tb{$reportId}->{'countryName'};
            my $sexFixed = %$tb{$reportId}->{'sexFixed'} // die;
            my $vaersSexName = $enums{'vaersSex'}->{$sexFixed} // die;
            my $vaersSource = %$tb{$reportId}->{'vaersSource'} // die;
            my $source;
            if ($vaersSource == 1) {
                $source = 'All Years Data';
            } else {
                $source = 'Non-Domestic'
            }
            my $patientAge = %$tb{$reportId}->{'patientAgeFixed'};
            my $vaccinationDate = %$tb{$reportId}->{'vaccinationDateFixed'};
            my $onsetDate = %$tb{$reportId}->{'onsetDateFixed'};
            my $permanentDisability = %$tb{$reportId}->{'permanentDisabilityFixed'} // die;
            my $hospitalized = %$tb{$reportId}->{'hospitalizedFixed'} // die;
            my $patientDied = %$tb{$reportId}->{'patientDiedFixed'} // die;
            my $lifeThreatning = %$tb{$reportId}->{'lifeThreatningFixed'} // die;
            my $symptomsListed = %$tb{$reportId}->{'symptomsListed'} // die;
            $symptomsListed = decode_json($symptomsListed);
            $hospitalized        = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
            $permanentDisability = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
            $lifeThreatning      = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
            $patientDied         = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
            my $compDate = $vaersReceptionDate;
            $compDate =~ s/\D//g;
            my %o = ();
            my $hasSymptom = 0;
            for my $symptomId (@$symptomsListed) {
                my $symptomName = $symptoms{$symptomId}->{'symptomName'} // die;
                $o{'symptoms'}->{$symptomName} = 1;
                if ($symptomFilter) {
                    $hasSymptom = 1 if exists $symptomsFiltered{$symptomId};
                }
            }
            if ($symptomFilter) {
                next unless $hasSymptom == 1;
            }
            if ($keywordsFilter) {
                my $hasKeyword = 0;
                for my $keyword (sort keys %keywordsFiltered) {
                    if ($keywordsFilter) {
                        $hasKeyword = 1 if $aEDescriptionNormalized =~ /$keyword/;
                    }
                }
                next unless $hasKeyword == 1;
            }

            $o{'vaersId'} = $vaersId;
            $o{'vaersReceptionDate'} = $vaersReceptionDate;
            $o{'aEDescription'} = $aEDescription;
            $o{'immProjectNumber'} = $immProjectNumber;
            $o{'countryName'} = $countryName;
            $o{'vaersSexName'} = $vaersSexName;
            $o{'source'} = $source;
            $o{'patientAge'} = $patientAge;
            $o{'vaccinationDate'} = $vaccinationDate;
            $o{'onsetDate'} = $onsetDate;
            $o{'permanentDisability'} = $permanentDisability;
            $o{'hospitalized'} = $hospitalized;
            $o{'patientDied'} = $patientDied;
            $o{'lifeThreatning'} = $lifeThreatning;
            for my $vaccineData (@$vaccinesListed) {
                push @{$o{'vaccines'}}, \%$vaccineData;
            }
            push @{$reports{$compDate}}, \%o;
            $exported++;
        }
    }
    open my $out, '>:utf8', "public/admin_exports/export_$userId.json";
    print $out encode_json\%reports;
    close $out;
    say "exported : $exported";

    $self->render(
        text => 'ok'
    );
}

1;