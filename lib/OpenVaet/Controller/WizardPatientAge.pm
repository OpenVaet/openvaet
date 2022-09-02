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

    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM vaers_deaths_report WHERE patientAgeConfirmationRequired = 1 AND patientAgeConfirmationTimestamp IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        operationsToPerform => $operationsToPerform,
        languages => \%languages
    );
}

sub load_next_report {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);
    my %enums = %{$self->enums()};

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName, discarded FROM vaers_deaths_symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        my $discarded   = %$sTb{$symptomId}->{'discarded'}   // die;
        $discarded      = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
        $symptoms{$symptomId}->{'discarded'}   = $discarded;
    }

    # Fetching confirmation target.
    my $operationsToPerform = $self->param('operationsToPerform') // die;
    my $sqlParam            = 'patientAgeConfirmationRequired';
    my $sqlValue            = 'patientAgeConfirmation';
    my $rTb                 = $self->dbh->selectrow_hashref("
        SELECT
            id as reportId,
            vaersId,
            vaccinesListed,
            vaersSexFixed,
            patientAgeFixed,
            creationTimestamp,
            aEDescription,
            vaersReceptionDate,
            onsetDate,
            deceasedDate,
            vaccinationDateFixed,
            onsetDateFixed,
            vaccinationDate,
            vaccinesListed,
            patientAgeConfirmation,
            patientAgeConfirmationRequired,
            hoursBetweenVaccineAndAE,
            hospitalized,
            permanentDisability,
            lifeThreatning,
            patientDied,
            symptomsListed
        FROM vaers_deaths_report
        WHERE
            $sqlValue IS NULL AND
            $sqlParam = 1 ORDER BY RAND()
        LIMIT 1", undef); # ORDER BY RAND()
    my $reportId                             = %$rTb{'reportId'}                        // die;
    my $vaersId                              = %$rTb{'vaersId'}                         // die;
    my $vaccinesListed                       = %$rTb{'vaccinesListed'}                  // die;
    my $vaersSexFixed                             = %$rTb{'vaersSexFixed'}                        // die;
    my $vaersSexName                         = $enums{'vaersSex'}->{$vaersSexFixed}          // die;
    my $patientAgeFixed                           = %$rTb{'patientAgeFixed'};
    my $hoursBetweenVaccineAndAE             = %$rTb{'hoursBetweenVaccineAndAE'};
    my $creationTimestamp                    = %$rTb{'creationTimestamp'}               // die;
    my $creationDatetime                     = time::timestamp_to_datetime($creationTimestamp);
    my $aEDescription                        = %$rTb{'aEDescription'}                   // die;
    my $vaersReceptionDate                   = %$rTb{'vaersReceptionDate'}              // die;
    my $patientAgeConfirmationRequired = %$rTb{'patientAgeConfirmationRequired'} // die;
    $patientAgeConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
    my $hospitalized                         = %$rTb{'hospitalized'}        // die;
    $hospitalized                            = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
    my $permanentDisability                  = %$rTb{'permanentDisability'} // die;
    $permanentDisability                     = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
    my $lifeThreatning                       = %$rTb{'lifeThreatning'}      // die;
    $lifeThreatning                          = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
    my $patientDied                          = %$rTb{'patientDied'}         // die;
    $patientDied                             = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
    my $vaccinationDate                      = %$rTb{'vaccinationDate'};
    my $onsetDate                            = %$rTb{'onsetDate'};
    my $vaccinationDateFixed                 = %$rTb{'vaccinationDateFixed'};
    my $onsetDateFixed                       = %$rTb{'onsetDateFixed'};
    my $patientAgeConfirmation         = %$rTb{'patientAgeConfirmation'};
    my $deceasedDate                              = %$rTb{'deceasedDate'};
    my ($deceasedYear, $deceasedMonth, $deceasedDay);
    if ($deceasedDate) {
        ($deceasedYear, $deceasedMonth, $deceasedDay) = split '-', $deceasedDate;
    }
    $vaccinesListed = decode_json($vaccinesListed);
    my $products;
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
    my $symptoms = '<div style="width:300px;margin:auto;"><ul>';
    for my $symptomId (@$symptomsListed) {
        my $symptomName = $symptoms{$symptomId}->{'symptomName'} // die;
        my $discarded   = $symptoms{$symptomId}->{'discarded'}   // die;
        $symptoms .= '<li><span>' . $symptomName . '</span></li>';
    }
    $symptoms .= '</ul></div>';
    my ($vaccinationYear, $vaccinationMonth, $vaccinationDay);
    if ($vaccinationDateFixed) {
        ($vaccinationYear, $vaccinationMonth, $vaccinationDay) = split '-', $vaccinationDateFixed;
    }
    my ($onsetYear, $onsetMonth, $onsetDay);
    if ($onsetDateFixed) {
        ($onsetYear, $onsetMonth, $onsetDay) = split '-', $onsetDateFixed;
    }

    my %sexes = ();
    $sexes{'1'}->{'sexName'} = 'Female';
    $sexes{'2'}->{'sexName'} = 'Male';
    $sexes{'3'}->{'sexName'} = 'Unknown';

    $self->render(
        currentLanguage                      => $currentLanguage,
        operationsToPerform                  => $operationsToPerform,
        hospitalized                         => $hospitalized,
        permanentDisability                  => $permanentDisability,
        lifeThreatning                       => $lifeThreatning,
        patientDied                          => $patientDied,
        sexes => \%sexes,
        reportId                             => $reportId,
        vaersId                              => $vaersId,
        symptoms                             => $symptoms,
        vaccinesListed                       => $vaccinesListed,
        vaersReceptionDate                   => $vaersReceptionDate,
        vaccinationDate                      => $vaccinationDate,
        vaccinationDateFixed                 => $vaccinationDateFixed,
        vaccinationYear                      => $vaccinationYear,
        vaccinationMonth                     => $vaccinationMonth,
        vaccinationDay                       => $vaccinationDay,
        onsetDate                            => $onsetDate,
        onsetDateFixed                       => $onsetDateFixed,
        onsetYear                            => $onsetYear,
        onsetMonth                           => $onsetMonth,
        onsetDay                             => $onsetDay,
        products                             => $products,
        deceasedYear                              => $deceasedYear,
        deceasedMonth                             => $deceasedMonth,
        deceasedDay                               => $deceasedDay,
        deceasedDate                              => $deceasedDate,
        vaersSexFixed                             => $vaersSexFixed,
        vaersSexName                         => $vaersSexName,
        aEDescription                        => $aEDescription,
        patientAgeFixed                           => $patientAgeFixed,
        creationDatetime                     => $creationDatetime,
        hoursBetweenVaccineAndAE             => $hoursBetweenVaccineAndAE,
        patientAgeConfirmation         => $patientAgeConfirmation,
        patientAgeConfirmationRequired => $patientAgeConfirmationRequired,
        sqlValue                             => $sqlValue,
        languages                            => \%languages
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
    my $vaersSexFixed     = $self->param('vaersSexFixed')   // die;
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
        UPDATE vaers_deaths_report SET
            $sqlValue = $value,
            patientAgeFixed = ?,
            vaersSexFixed = ?,
            vaccinationDateFixed = ?,
            onsetDateFixed = ?,
            deceasedDateFixed = ?,
            hoursBetweenVaccineAndAE = ?,
            patientDiedFixed = $patientDied,
            lifeThreatningFixed = $lifeThreatning,
            permanentDisabilityFixed = $permanentDisability,
            hospitalizedFixed = $hospitalized,
            patientAgeConfirmationTimestamp = UNIX_TIMESTAMP(),
            userId = ?
        WHERE id = $reportId");
    $sth->execute(
        $patientAgeFixed,
        $vaersSexFixed,
        $vaccinationDateFixed,
        $onsetDateFixed,
        $deceasedDateFixed,
        $hoursBetweenVaccineAndAE,
        $userId
    ) or die $sth->err();

    say "reportId : $reportId";

    $self->render(text => 'ok');
}

sub patient_ages_completed {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my %reports = ();
    my ($agesCompleted, $totalReports) = (0, 0);
    my $tb = $self->dbh->selectall_hashref("
        SELECT
            vaers_deaths_report.id as vaersDeathsReportId,
            vaers_deaths_report.patientAgeFixed,
            vaers_deaths_report.vaersId,
            vaers_deaths_report.patientAgeConfirmationTimestamp,
            vaers_deaths_report.userId,
            user.email 
        FROM vaers_deaths_report
            LEFT JOIN user ON user.id = vaers_deaths_report.userId
        WHERE patientAgeConfirmationTimestamp IS NOT NULL
    ", 'vaersDeathsReportId');
    for my $vaersDeathsReportId (sort{$a <=> $b} keys %$tb) {
        my $patientAgeFixed                 = %$tb{$vaersDeathsReportId}->{'patientAgeFixed'};
        my $patientAgeConfirmationTimestamp = %$tb{$vaersDeathsReportId}->{'patientAgeConfirmationTimestamp'} // die;
        my $userId                          = %$tb{$vaersDeathsReportId}->{'userId'}                          // die;
        my $vaersId                           = %$tb{$vaersDeathsReportId}->{'vaersId'}                           // die;
        my $email                           = %$tb{$vaersDeathsReportId}->{'email'}                           // die;
        my $patientAgeConfirmationDatetime  = time::timestamp_to_datetime($patientAgeConfirmationTimestamp);
        my ($userName) = split '\@', $email;
        $agesCompleted++ if defined $patientAgeFixed;
        $totalReports++;
        $reports{$patientAgeConfirmationTimestamp}->{$vaersDeathsReportId}->{'patientAgeConfirmationDatetime'} = $patientAgeConfirmationDatetime;
        $reports{$patientAgeConfirmationTimestamp}->{$vaersDeathsReportId}->{'patientAgeFixed'} = $patientAgeFixed;
        $reports{$patientAgeConfirmationTimestamp}->{$vaersDeathsReportId}->{'userName'} = $userName;
        $reports{$patientAgeConfirmationTimestamp}->{$vaersDeathsReportId}->{'vaersId'} = $vaersId;
    }
    my $agesCompletedPercent = nearest(0.01, $agesCompleted * 100 / $totalReports);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        agesCompleted => $agesCompleted,
        totalReports => $totalReports,
        agesCompletedPercent => $agesCompletedPercent,
        languages => \%languages,
        reports => \%reports
    );
}

sub reset_report_attributes {
    my $self = shift;
    my $vaersDeathsReportId = $self->param('vaersDeathsReportId') // die;

    say "vaersDeathsReportId : $vaersDeathsReportId";
    my $sth = $self->dbh->prepare("UPDATE vaers_deaths_report SET patientAgeConfirmation = NULL, patientAgeConfirmationTimestamp = NULL, userId = NULL WHERE id = $vaersDeathsReportId");
    $sth->execute() or die $sth->err();

    $self->render(text => 'ok');
}

1;