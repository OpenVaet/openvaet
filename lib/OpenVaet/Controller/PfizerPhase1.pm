package OpenVaet::Controller::PfizerPhase1;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use time;

sub calc_days_difference {
    my ($date1, $date2) = @_;
    die unless $date1 && $date2;
    my $date1Ftd = datetime_from_compdate($date1);
    my $date2Ftd = datetime_from_compdate($date2);
    # say "date1Ftd : $date1Ftd";
    # say "date2Ftd : $date2Ftd";
    my $daysDifference = time::calculate_days_difference($date1Ftd, $date2Ftd);
    return $daysDifference;
}

sub date_from_compdate {
    my ($date) = shift;
    my ($y, $m, $d) = $date =~ /(....)(..)(..)/;
    die unless $y && $m && $d;
    return "$y-$m-$d";
}

sub datetime_from_compdate {
    my ($date) = shift;
    my ($y, $m, $d) = $date =~ /(....)(..)(..)/;
    die unless $y && $m && $d;
    return "$y-$m-$d 12:00:00";
}

sub json_from_file {
    my $file = shift;
    if (-f $file) {
        my $json;
        eval {
            open my $in, '<:utf8', $file;
            while (<$in>) {
                $json .= $_;
            }
            close $in;
            $json = decode_json($json) or die $!;
        };
        if ($@) {
            {
                local $/;
                open (my $fh, $file) or die $!;
                $json = <$fh>;
                close $fh;
            }
            eval {
                $json = decode_json($json);
            };
            if ($@) {
                die "failed parsing json : " . @!;
            }
        }
        return %$json;
    } else {
        return {};
    }
}

sub pfizer_phase_1 {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my %phase1Subjects = json_from_file('public/doc/pfizer_trials/phase1SubjectsByScreeningDate.json');
    # p%phase1Subjects;

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        phase1Subjects => \%phase1Subjects
    );
}

sub phase_1_subject {
    my $self = shift;

    my $subjectId      = $self->param('subjectId')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;

    my %subjectData = json_from_file('public/doc/pfizer_trials/phase1Subjects.json');
    %subjectData = %{$subjectData{$subjectId}};

    $self->render(
        currentLanguage     => $currentLanguage,
        subjectId     => $subjectId,
        subjectData => \%subjectData
    );
}


sub study_changelog {
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

1;