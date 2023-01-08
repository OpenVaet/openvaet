package OpenVaet::Controller::PfizerTimeline;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Scalar::Util qw(looks_like_number);
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;
no autovivification;

sub pfizer_timeline {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading timeline json.
    my $timelineJson;
    # open my $in, '<:utf8', 'raw_data/pfizer_trials/timelines/example.json';
    open my $in, '<:utf8', 'tasks/pfizer_trials/trial_timeline.json';
    while (<$in>) {
    	$timelineJson .= $_;
    }
    close $in;
    $timelineJson = decode_json($timelineJson);
    $timelineJson = encode_json\%$timelineJson;
    $timelineJson =~ s/\'/\\\'/g;
    $timelineJson =~ s/\"/\\\"/g;
    # $timelineJson = decode_json($timelineJson);
    # my %timelineJson = %$timelineJson;

    $self->render(
    	# timelineJson => \%timelineJson,
    	timelineJson => $timelineJson,
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

1;