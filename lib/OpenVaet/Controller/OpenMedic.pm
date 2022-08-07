package OpenVaet::Controller::OpenMedic;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Math::Round qw(nearest);
use Data::Printer;
use FindBin;
use File::stat;
use lib "$FindBin::Bin/../lib";
use session;

sub open_medic {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Getting OpenMedic stats.
    my %openMedicStats = ();
    open my $in, '<:utf8', 'stats/openmedic_stats.json';
    my $openMedicJson;
    while (<$in>) {
        $openMedicJson .= $_;
    }
    close $in,
    my $openMedicStats = decode_json($openMedicJson);
    %openMedicStats = %$openMedicStats;
    # p$openMedicStats{'openMedic'}->{'byGroups'};

    # Getting MedicAM stats.
    my %medicAmStats = ();
    open $in, '<:utf8', 'stats/medicam_stats.json';
    my $medicAmJson;
    while (<$in>) {
        $medicAmJson .= $_;
    }
    close $in,
    my $medicAmStats = decode_json($medicAmJson);
    %medicAmStats = %$medicAmStats;
    # p$medicAmStats{'medicAm'}->{'byGroups'};
    p%medicAmStats;

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        openMedicStats => \%openMedicStats,
        medicAmStats => \%medicAmStats
    );
}

1;