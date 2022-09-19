package OpenVaet::Controller::DataAdmin;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub data_admin {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub symptoms_sets {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    # Loads user symptoms & common symptoms.
    my %symptomsSets = ();
    my $tb = $self->dbh->selectall_hashref("SELECT id as symptomsSetId, name as symptomsSetName, userId, symptoms FROM symptoms_set", 'symptomsSetId');
    for my $symptomsSetId (sort{$a <=> $b} keys %$tb) {
        my $symptomsSetName = %$tb{$symptomsSetId}->{'symptomsSetName'} // die;
        my $userId = %$tb{$symptomsSetId}->{'userId'} // die;
        my $symptoms = %$tb{$symptomsSetId}->{'symptoms'};
        my $totalSymptoms = 0;
        if ($symptoms) {
            $symptoms = decode_json($symptoms);
            my @symptoms = @$symptoms;
            $totalSymptoms = scalar @symptoms;
        }
        if ($userId eq $sessionUserId) {
            $symptomsSets{'owned'}->{$symptomsSetName}->{'symptomsSetId'} = $symptomsSetId;
            $symptomsSets{'owned'}->{$symptomsSetName}->{'totalSymptoms'} = $totalSymptoms;
        } else {
            $symptomsSets{'notOwned'}->{$symptomsSetName}->{'symptomsSetId'} = $symptomsSetId;
            $symptomsSets{'notOwned'}->{$symptomsSetName}->{'totalSymptoms'} = $totalSymptoms;
        }
    }

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        symptomsSets => \%symptomsSets
    );
}

sub edit_symptoms_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $symptomsSetId   = $self->param('symptomsSetId')   // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    # Loads user symptoms & common symptoms.
    my %symptoms = ();
    my $tbS = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$tbS) {
        my $symptomName = %$tbS{$symptomId}->{'symptomName'} // die;
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
        $symptoms{$symptomId}->{'active'} = 0;
    }
    my $tb = $self->dbh->selectrow_hashref("SELECT name as symptomsSetName, userId, symptoms FROM symptoms_set WHERE id = $symptomsSetId", undef) or die;
    my $symptomsSetName = %$tb{'symptomsSetName'} // die;
    my $userId = %$tb{'userId'} // die;
    my $symptoms = %$tb{'symptoms'};
    if ($symptoms) {
        $symptoms = decode_json($symptoms);
        my @symptoms = @$symptoms;
        for my $symptomId (@symptoms) {
            die unless exists $symptoms{$symptomId}->{'symptomName'};
            $symptoms{$symptomId}->{'active'} = 1;
        }
    }
    my $canEdit = 0;
    if ($userId eq $sessionUserId) {
        $canEdit = 1;
    }

    $self->render(
        currentLanguage => $currentLanguage,
        symptomsSetId => $symptomsSetId,
        symptomsSetName => $symptomsSetName,
        canEdit => $canEdit,
        languages => \%languages,
        symptoms => \%symptoms
    );
}

sub new_symptoms_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub save_symptoms_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $symptomsSetName = $self->param('symptomsSetName') // die;

    my $userId = $self->session("userId") // die;

    my %json = ();
    $json{'status'} = 'ok';
    $json{'message'} = '';

    # Verify if the name already exists.
    my $tb = $self->dbh->selectrow_hashref("SELECT id FROM symptoms_set WHERE name = ?", undef, $symptomsSetName);
    if (keys %$tb) {
        $json{'status'} = 'ko';
        if ($currentLanguage eq 'fr') {
            $json{'message'} = 'Ce set de symptomes existe déjà';
        } else {
            $json{'message'} = 'This set of symptoms already exists';
        }
    } else {

        # If the name doesn't exist, proceeding with creation.
        my $sth = $self->dbh->prepare("INSERT INTO symptoms_set (name, userId) VALUES (?, $userId)");
        $sth->execute($symptomsSetName) or die $sth->err();
    }

    $self->render(
        json => \%json
    );
}

sub set_symptom_activity {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $symptomId       = $self->param('symptomId')       // die;
    my $symptomsSetId   = $self->param('symptomsSetId')   // die;
    my $activity        = $self->param('activity')        // die;

    my $tb        = $self->dbh->selectrow_hashref("SELECT symptoms FROM symptoms_set WHERE id = $symptomsSetId", undef) or die;
    my $symptoms  = %$tb{'symptoms'};
    my @symptoms  = ();
    if ($activity == 0) {
        $symptoms = decode_json($symptoms);
        my @sts   = @$symptoms;
        for my $sId (@sts) {
            unless ($sId eq $symptomId) {
                push @symptoms, $sId;
            }
        }
    } else {
        if ($symptoms) {
            $symptoms = decode_json($symptoms);
            my @sts   = @$symptoms;
            for my $sId (@sts) {
                push @symptoms, $sId;
            }
        }
        push @symptoms, $symptomId;
    }
    $symptoms = encode_json\@symptoms;

    my $sth = $self->dbh->prepare("UPDATE symptoms_set SET symptoms = ? WHERE id = $symptomsSetId");
    $sth->execute($symptoms) or die $sth->err();

    $self->render(
        text => 'ok'
    );
}

sub keywords_sets {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    # Loads user keywords & common keywords.
    my %keywordsSets = ();
    my $tb = $self->dbh->selectall_hashref("SELECT id as keywordsSetId, name as keywordsSetName, userId, keywords FROM keywords_set", 'keywordsSetId');
    for my $keywordsSetId (sort{$a <=> $b} keys %$tb) {
        my $keywordsSetName = %$tb{$keywordsSetId}->{'keywordsSetName'} // die;
        my $userId = %$tb{$keywordsSetId}->{'userId'} // die;
        my $keywords = %$tb{$keywordsSetId}->{'keywords'};
        my $totalKeywords = 0;
        if ($keywords) {
            my @keywords = split '<br \/>', $keywords;
            $totalKeywords = scalar @keywords;
        }
        if ($userId eq $sessionUserId) {
            $keywordsSets{'owned'}->{$keywordsSetName}->{'keywordsSetId'} = $keywordsSetId;
            $keywordsSets{'owned'}->{$keywordsSetName}->{'totalKeywords'} = $totalKeywords;
        } else {
            $keywordsSets{'notOwned'}->{$keywordsSetName}->{'keywordsSetId'} = $keywordsSetId;
            $keywordsSets{'notOwned'}->{$keywordsSetName}->{'totalKeywords'} = $totalKeywords;
        }
    }

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        keywordsSets => \%keywordsSets
    );
}

sub new_keywords_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub save_keywords_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $keywordsSetName = $self->param('keywordsSetName') // die;

    my $userId = $self->session("userId") // die;

    my %json = ();
    $json{'status'} = 'ok';
    $json{'message'} = '';

    # Verify if the name already exists.
    my $tb = $self->dbh->selectrow_hashref("SELECT id FROM keywords_set WHERE name = ?", undef, $keywordsSetName);
    if (keys %$tb) {
        $json{'status'} = 'ko';
        if ($currentLanguage eq 'fr') {
            $json{'message'} = 'Ce set de keywordes existe déjà';
        } else {
            $json{'message'} = 'This set of keywords already exists';
        }
    } else {

        # If the name doesn't exist, proceeding with creation.
        my $sth = $self->dbh->prepare("INSERT INTO keywords_set (name, userId) VALUES (?, $userId)");
        $sth->execute($keywordsSetName) or die $sth->err();
    }

    $self->render(
        json => \%json
    );
}

sub edit_keywords_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $keywordsSetId   = $self->param('keywordsSetId')   // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    # Loads user keywords & common keywords.
    my $tb = $self->dbh->selectrow_hashref("SELECT name as keywordsSetName, userId, keywords FROM keywords_set WHERE id = $keywordsSetId", undef) or die;
    my $keywordsSetName = %$tb{'keywordsSetName'} // die;
    my $userId = %$tb{'userId'} // die;
    my $keywords = %$tb{'keywords'};
    my $canEdit = 0;
    if ($userId eq $sessionUserId) {
        $canEdit = 1;
    }

    $self->render(
        currentLanguage => $currentLanguage,
        keywordsSetId => $keywordsSetId,
        keywordsSetName => $keywordsSetName,
        canEdit => $canEdit,
        languages => \%languages,
        keywords => $keywords
    );
}

sub save_keywords {
    my $self = shift;
    my $keywords = $self->param("keywords");
    $keywords    =~ s/\"//;
    $keywords    =~ s/\"$//;
    my $keywordsSetId   = $self->param('keywordsSetId')   // die;
    my $sth = $self->dbh->prepare("UPDATE keywords_set SET keywords = ? WHERE id = $keywordsSetId");
    $sth->execute($keywords) or die $sth->err();
    $self->render(
        text => 'ok'
    );
}

1;