package OpenVaet::Controller::WizardPregnanciesSeriousnessConfirmation;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

my $pregnancySeriousnessData     = 'Pregnancy Complications Related';
my %pregnancySeriousnessSymptoms = ();
my %pregnancySeriousnessKeywords = ();

sub wizard_pregnancies_seriousness_confirmation {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $reportId        = $self->param('reportId');

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching current batch.
    my $operationsToPerform;
    if ($reportId) {
        $operationsToPerform = 1;
    } else {
        $operationsToPerform = operations_to_perform($self);
    }
    say "operationsToPerform: $operationsToPerform";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        reportId => $reportId,
        currentLanguage => $currentLanguage,
        operationsToPerform => $operationsToPerform,
        languages => \%languages
    );
}

sub operations_to_perform {
    my $self = shift;
    my $operationsToPerform = 0;
    my $wTb1 = $self->dbh->selectrow_hashref("SELECT count(id) as currentWizardTasks FROM pregnancy_seriousness_wizard_report WHERE pregnancySeriousnessConfirmationRequired = 1 AND pregnancySeriousnessConfirmation IS NULL", undef);
    my $wTb2 = $self->dbh->selectrow_hashref("SELECT count(id) as totalWizardTasks   FROM pregnancy_seriousness_wizard_report WHERE pregnancySeriousnessConfirmationRequired = 1", undef);
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

            # Truncating pregnancy_seriousness_wizard_report table.
            my $sth = $self->dbh->prepare("TRUNCATE pregnancy_seriousness_wizard_report");
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
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE pregnancySeriousnessConfirmationRequired = 1 AND pregnancySeriousnessConfirmation IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql                 = "
            SELECT
                id as reportId,
                pregnancySeriousnessConfirmation,
                pregnancySeriousnessConfirmationRequired,
                pregnancySeriousnessConfirmationTimestamp
            FROM report
            WHERE 
                pregnancySeriousnessConfirmationRequired = 1 AND
                pregnancySeriousnessConfirmation IS NULL
            ORDER BY RAND()
            LIMIT $treatmentLimit";
        say "$sql";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $pregnancySeriousnessConfirmationRequired       = %$rTb{$reportId}->{'pregnancySeriousnessConfirmationRequired'} // die;
            $pregnancySeriousnessConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmationRequired, -32)));
            my $pregnancySeriousnessConfirmation               = %$rTb{$reportId}->{'pregnancySeriousnessConfirmation'};
            # $pregnancySeriousnessConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmation, -32)));
            my $pregnancySeriousnessConfirmationTimestamp      = %$rTb{$reportId}->{'pregnancySeriousnessConfirmationTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO pregnancy_seriousness_wizard_report (reportId, pregnancySeriousnessConfirmationRequired, pregnancySeriousnessConfirmation, pregnancySeriousnessConfirmationTimestamp) VALUES (?, $pregnancySeriousnessConfirmationRequired, NULL, ?)");
            $sth->execute($reportId, $pregnancySeriousnessConfirmationTimestamp) or die $sth->err();
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
    my $environment     = $config{'environment'}    // die;
    my $mainWidth       = $self->param('mainWidth') // die;
    my $reportId        = $self->param('reportId');

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
    }

    load_pregnancy_seriousness_symptoms($self);
    load_pregnancy_seriousness_keywords($self);

    # Fetching post_treatment target.
    # Fetching total operations to perform.
    my $operationsToPerform = operations_to_perform($self);

    my ($hospitalized, $permanentDisability, $lifeThreatning, $patientDied,
        $vaersId, $symptoms, $vaccinesListed, $vaersReceptionDate, $vaccinationDate,
        $vaccinationDateFixed, $vaccinationYear, $vaccinationMonth, $vaccinationDay, $onsetDate,
        $onsetDateFixed, $onsetYear, $onsetMonth, $onsetDay, $products,
        $deceasedYear, $deceasedMonth, $deceasedDay, $deceasedDate, $sexFixed,
        $vaersSexName, $aEDescription, $patientAgeFixed, $creationDatetime, $hoursBetweenVaccineAndAE,
        $pregnancySeriousnessConfirmation, $pregnancySeriousnessConfirmationRequired, $notes, $childDied, $childSeriousAE);
    my $sqlParam            = 'pregnancySeriousnessConfirmationRequired';
    my $sqlValue            = 'pregnancySeriousnessConfirmation';
    my $comesFromDirectReport = 0;
    if ($operationsToPerform) {
        my $sql;
        if ($reportId) {
            $comesFromDirectReport = 1;
            $sql                   = "
                SELECT
                    pregnancy_seriousness_wizard_report.reportId,
                    report.vaersId,
                    report.vaccinesListed,
                    report.sexFixed,
                    report.patientAgeFixed,
                    report.creationTimestamp,
                    report.aEDescription,
                    report.vaersReceptionDate,
                    report.onsetDate,
                    report.deceasedDate,
                    report.notes,
                    report.vaccinationDateFixed,
                    report.onsetDateFixed,
                    report.vaccinationDate,
                    report.vaccinesListed,
                    report.pregnancySeriousnessConfirmation,
                    report.pregnancySeriousnessConfirmationRequired,
                    report.hoursBetweenVaccineAndAE,
                    report.childDied,
                    report.childSeriousAE,
                    report.hospitalizedFixed as hospitalized,
                    report.permanentDisabilityFixed as permanentDisability,
                    report.lifeThreatningFixed as lifeThreatning,
                    report.patientDiedFixed as patientDied,
                    report.symptomsListed
                FROM pregnancy_seriousness_wizard_report
                    LEFT JOIN report ON report.id = pregnancy_seriousness_wizard_report.reportId
                WHERE 
                    report.id = $reportId
                ORDER BY RAND()
                LIMIT 1";
        } else {
            $sql                 = "
                SELECT
                    pregnancy_seriousness_wizard_report.reportId,
                    report.vaersId,
                    report.vaccinesListed,
                    report.sexFixed,
                    report.patientAgeFixed,
                    report.creationTimestamp,
                    report.aEDescription,
                    report.vaersReceptionDate,
                    report.onsetDate,
                    report.deceasedDate,
                    report.notes,
                    report.vaccinationDateFixed,
                    report.onsetDateFixed,
                    report.vaccinationDate,
                    report.vaccinesListed,
                    report.pregnancySeriousnessConfirmation,
                    report.pregnancySeriousnessConfirmationRequired,
                    report.hoursBetweenVaccineAndAE,
                    report.childDied,
                    report.childSeriousAE,
                    report.hospitalizedFixed as hospitalized,
                    report.permanentDisabilityFixed as permanentDisability,
                    report.lifeThreatningFixed as lifeThreatning,
                    report.patientDiedFixed as patientDied,
                    report.symptomsListed
                FROM pregnancy_seriousness_wizard_report
                    LEFT JOIN report ON report.id = pregnancy_seriousness_wizard_report.reportId
                WHERE 
                    pregnancy_seriousness_wizard_report.$sqlParam = 1 AND
                    pregnancy_seriousness_wizard_report.$sqlValue IS NULL
                ORDER BY RAND()
                LIMIT 1";
        }
        say "$sql";
        my $rTb                                  = $self->dbh->selectrow_hashref($sql, undef); # ORDER BY RAND()
        $reportId                                = %$rTb{'reportId'}                        // die;
        $vaersId                                 = %$rTb{'vaersId'}                         // die;
        $vaccinesListed                          = %$rTb{'vaccinesListed'}                  // die;
        $sexFixed                                = %$rTb{'sexFixed'}                        // die;
        $vaersSexName                            = $enums{'vaersSex'}->{$sexFixed}          // die;
        $patientAgeFixed                         = %$rTb{'patientAgeFixed'};
        $hoursBetweenVaccineAndAE                = %$rTb{'hoursBetweenVaccineAndAE'};
        my $creationTimestamp                    = %$rTb{'creationTimestamp'}               // die;
        $creationDatetime                        = time::timestamp_to_datetime($creationTimestamp);
        $aEDescription                           = %$rTb{'aEDescription'}                   // die;
        $vaersReceptionDate                      = %$rTb{'vaersReceptionDate'}              // die;
        $pregnancySeriousnessConfirmationRequired = %$rTb{'pregnancySeriousnessConfirmationRequired'} // die;
        $pregnancySeriousnessConfirmationRequired = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmationRequired, -32)));
        $hospitalized                            = %$rTb{'hospitalized'}        // die;
        $hospitalized                            = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
        $permanentDisability                     = %$rTb{'permanentDisability'} // die;
        $permanentDisability                     = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
        $lifeThreatning                          = %$rTb{'lifeThreatning'}      // die;
        $lifeThreatning                          = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
        $patientDied                             = %$rTb{'patientDied'}         // die;
        $patientDied                             = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
        $childDied                               = %$rTb{'childDied'}      // die;
        $childDied                               = unpack("N", pack("B32", substr("0" x 32 . $childDied, -32)));
        $childSeriousAE                          = %$rTb{'childSeriousAE'}         // die;
        $childSeriousAE                          = unpack("N", pack("B32", substr("0" x 32 . $childSeriousAE, -32)));
        $vaccinationDate                         = %$rTb{'vaccinationDate'};
        $onsetDate                               = %$rTb{'onsetDate'};
        $vaccinationDateFixed                    = %$rTb{'vaccinationDateFixed'};
        $onsetDateFixed                          = %$rTb{'onsetDateFixed'};
        $pregnancySeriousnessConfirmation         = %$rTb{'pregnancySeriousnessConfirmation'};
        $deceasedDate                            = %$rTb{'deceasedDate'};
        if ($deceasedDate) {
            ($deceasedYear, $deceasedMonth, $deceasedDay) = split '-', $deceasedDate;
        }
        $notes                                   = %$rTb{'notes'};
        $vaccinesListed = decode_json($vaccinesListed);
        for my $vaccineData (@$vaccinesListed) {
            my $substanceShortenedName = %$vaccineData{'substanceShortenedName'} // die;
            my $dose = %$vaccineData{'dose'} // die;
            $products .= "<li><span>$substanceShortenedName (dose $dose)</span></li>";
        }

        for my $hl (sort keys %pregnancySeriousnessKeywords) {
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
            if (exists $pregnancySeriousnessSymptoms{$symptomId}) {
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
        currentLanguage                         => $currentLanguage,
        comesFromDirectReport                   => $comesFromDirectReport,
        sqlValue                                => $sqlValue,
        operationsToPerform                     => $operationsToPerform,
        hospitalized                            => $hospitalized,
        permanentDisability                     => $permanentDisability,
        lifeThreatning                          => $lifeThreatning,
        patientDied                             => $patientDied,
        childDied                               => $childDied,
        childSeriousAE                          => $childSeriousAE,
        reportId                                => $reportId,
        vaersId                                 => $vaersId,
        symptoms                                => $symptoms,
        notes                                   => $notes,
        vaccinesListed                          => $vaccinesListed,
        vaersReceptionDate                      => $vaersReceptionDate,
        vaccinationDate                         => $vaccinationDate,
        vaccinationDateFixed                    => $vaccinationDateFixed,
        vaccinationYear                         => $vaccinationYear,
        vaccinationMonth                        => $vaccinationMonth,
        vaccinationDay                          => $vaccinationDay,
        onsetDate                               => $onsetDate,
        onsetDateFixed                          => $onsetDateFixed,
        onsetYear                               => $onsetYear,
        onsetMonth                              => $onsetMonth,
        onsetDay                                => $onsetDay,
        products                                => $products,
        deceasedYear                            => $deceasedYear,
        deceasedMonth                           => $deceasedMonth,
        deceasedDay                             => $deceasedDay,
        deceasedDate                            => $deceasedDate,
        sexFixed                                => $sexFixed,
        mainWidth                               => $mainWidth,
        vaersSexName                            => $vaersSexName,
        aEDescription                           => $aEDescription,
        patientAgeFixed                         => $patientAgeFixed,
        creationDatetime                        => $creationDatetime,
        hoursBetweenVaccineAndAE                => $hoursBetweenVaccineAndAE,
        pregnancySeriousnessConfirmation         => $pregnancySeriousnessConfirmation,
        pregnancySeriousnessConfirmationRequired => $pregnancySeriousnessConfirmationRequired,
        sexes                                   => \%sexes,
        languages                               => \%languages
    );
}

sub load_pregnancy_seriousness_symptoms {
    my $self = shift;
    my $pregnancySeriousnessSymptomsSetId = get_pregnancy_seriousness_symptoms_set($self);
    my $tb = $self->dbh->selectrow_hashref("SELECT symptoms FROM symptoms_set WHERE id = $pregnancySeriousnessSymptomsSetId", undef);
    die unless keys %$tb;
    my $symptoms = %$tb{'symptoms'} // die;
    $symptoms = decode_json($symptoms);
    for my $symptomId (@$symptoms) {
        $pregnancySeriousnessSymptoms{$symptomId} = 1;
    }
}

sub load_pregnancy_seriousness_keywords {
    my $self = shift;
    my $pregnancySeriousnessKeywordsSetId = get_pregnancy_seriousness_keywords_set($self);
    my $tb = $self->dbh->selectrow_hashref("SELECT keywords FROM keywords_set WHERE id = $pregnancySeriousnessKeywordsSetId", undef);
    die unless keys %$tb;
    my $keywords = %$tb{'keywords'} // die;
    my @keywordsFiltered = split '<br \/>', $keywords;
    for my $keyword (@keywordsFiltered) {
        my $lcKeyword = lc $keyword;
        $pregnancySeriousnessKeywords{$lcKeyword} = 1;
    }
}

sub get_pregnancy_seriousness_symptoms_set {
    my $self = shift;
    my $tb = $self->dbh->selectrow_hashref("SELECT id as symptomsSetId FROM symptoms_set WHERE name = ?", undef, $pregnancySeriousnessData);
    die unless keys %$tb;
    return %$tb{'symptomsSetId'};
}

sub get_pregnancy_seriousness_keywords_set {
    my $self = shift;
    my $tb = $self->dbh->selectrow_hashref("SELECT id as keywordsSetId FROM keywords_set WHERE name = ?", undef, $pregnancySeriousnessData);
    die unless keys %$tb;
    return %$tb{'keywordsSetId'};
}

sub set_report_attribute {
    my $self              = shift;
    my $reportId          = $self->param('reportId')        // die;
    my $sqlValue          = $self->param('sqlValue')        // die;
    my $value             = $self->param('value')           // die;
    my $userId            = $self->session('userId')        // die;
    my $childDied         = $self->param('childDied')       // die;
    my $childSeriousAE    = $self->param('childSeriousAE')  // die;
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
    my $notes   = $self->param('notes') // die;
    $notes    =~ s/\"//;
    $notes    =~ s/\"$//;
    my $sth = $self->dbh->prepare("
        UPDATE report SET
            $sqlValue = $value,
            notes = ?,
            childDied = $childDied,
            childSeriousAE = $childSeriousAE,
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
            pregnancySeriousnessConfirmationTimestamp = UNIX_TIMESTAMP(),
            pregnancySeriousnessConfirmationUserId = ?
        WHERE id = $reportId");
    $sth->execute(
        $notes,
        $patientAgeFixed,
        $sexFixed,
        $vaccinationDateFixed,
        $onsetDateFixed,
        $deceasedDateFixed,
        $hoursBetweenVaccineAndAE,
        $userId
    ) or die $sth->err();
    my $sth2 = $self->dbh->prepare("
        UPDATE pregnancy_seriousness_wizard_report SET
            $sqlValue = $value,
            pregnancySeriousnessConfirmationTimestamp = UNIX_TIMESTAMP()
        WHERE reportId = $reportId");
    $sth2->execute(
    ) or die $sth2->err();

    say "reportId : $reportId";

    $self->render(text => 'ok');
}

sub pregnancies_seriousness_confirmation_completed {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $adminFilter     = $self->param('adminFilter');
    my $productFilter   = $self->param('productFilter');
    say "productFilter : $productFilter";

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my %reports = ();
    my ($pregnancySeriousnessConfirmed, $totalReports) = (0, 0);
    my %admins = ();
    my %products = ();
    my $sql = "
        SELECT
            report.id as reportId,
            report.pregnancySeriousnessConfirmation,
            report.vaersId,
            report.vaccinesListed,
            report.pregnancySeriousnessConfirmationTimestamp,
            report.pregnancySeriousnessConfirmationUserId,
            user.email 
        FROM report
            LEFT JOIN user ON user.id = report.pregnancySeriousnessConfirmationUserId
        WHERE pregnancySeriousnessConfirmationTimestamp IS NOT NULL
    ";
    say $sql;
    my $tb = $self->dbh->selectall_hashref($sql, 'reportId');
    my $loaded = 0;
    for my $reportId (sort{$a <=> $b} keys %$tb) {
        my $pregnancySeriousnessConfirmation = %$tb{$reportId}->{'pregnancySeriousnessConfirmation'} // die;
        $pregnancySeriousnessConfirmation    = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmation, -32)));
        my $pregnancySeriousnessConfirmationTimestamp = %$tb{$reportId}->{'pregnancySeriousnessConfirmationTimestamp'} // die;
        my $pregnancySeriousnessConfirmationDatetime  = time::timestamp_to_datetime($pregnancySeriousnessConfirmationTimestamp);
        my $pregnancySeriousnessConfirmationUserId                          = %$tb{$reportId}->{'pregnancySeriousnessConfirmationUserId'}                          // die;
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
        $pregnancySeriousnessConfirmed++ if $pregnancySeriousnessConfirmation;
        $totalReports++;
        for my $substanceShortenedName (sort keys %vax) {
            $reports{$pregnancySeriousnessConfirmationTimestamp}->{$reportId}->{'products'}->{$substanceShortenedName} = 1;
        }
        $reports{$pregnancySeriousnessConfirmationTimestamp}->{$reportId}->{'pregnancySeriousnessConfirmationDatetime'} = $pregnancySeriousnessConfirmationDatetime;
        $reports{$pregnancySeriousnessConfirmationTimestamp}->{$reportId}->{'pregnancySeriousnessConfirmation'} = $pregnancySeriousnessConfirmation;
        $reports{$pregnancySeriousnessConfirmationTimestamp}->{$reportId}->{'userName'} = $userName;
        $reports{$pregnancySeriousnessConfirmationTimestamp}->{$reportId}->{'vaersId'} = $vaersId;
    }
    my $pregnancySeriousnessConfirmedPercent = 0;
    if ($totalReports) {
        $pregnancySeriousnessConfirmedPercent = nearest(0.01, $pregnancySeriousnessConfirmed * 100 / $totalReports);
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        adminFilter => $adminFilter,
        productFilter => $productFilter,
        pregnancySeriousnessConfirmed => $pregnancySeriousnessConfirmed,
        totalReports => $totalReports,
        pregnancySeriousnessConfirmedPercent => $pregnancySeriousnessConfirmedPercent,
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
    my $sth = $self->dbh->prepare("UPDATE report SET pregnancySeriousnessConfirmation = NULL, pregnancySeriousnessConfirmationTimestamp = NULL, pregnancySeriousnessConfirmationUserId = NULL WHERE id = $reportId");
    $sth->execute() or die $sth->err();

    $self->render(text => 'ok');
}

1;