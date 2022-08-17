package OpenVaet::Controller::ChildrenVaers;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

sub children_vaers {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $vaccinesChildrenJson;
    open my $in, '<:utf8', 'stats/vaccines_children_reports_by_dates.json';
    while (<$in>) {
        $vaccinesChildrenJson .= $_;
    }
    close $in;
    $vaccinesChildrenJson = decode_json($vaccinesChildrenJson);
    my %vaccinesChildren = %$vaccinesChildrenJson;
    my $earliestCovidDate = $vaccinesChildren{'earliestCovidDate'} // die;
    my ($y, $m, $d) = $earliestCovidDate =~ /(....)(..)(..)/;
    $earliestCovidDate = "$y-$m-$d";

    my $vaccinesChildrenJsonForeign;
    open $in, '<:utf8', 'stats/foreign_vaccines_children_reports_by_dates.json';
    while (<$in>) {
        $vaccinesChildrenJsonForeign .= $_;
    }
    close $in;
    $vaccinesChildrenJsonForeign = decode_json($vaccinesChildrenJsonForeign);
    my %vaccinesChildrenForeign = %$vaccinesChildrenJsonForeign;
    my $earliestCovidDateForeign = $vaccinesChildrenForeign{'earliestCovidDate'} // die;
    ($y, $m, $d) = $earliestCovidDateForeign =~ /(....)(..)(..)/;
    $earliestCovidDateForeign = "$y-$m-$d";


    $self->render(
        earliestCovidDate => $earliestCovidDate,
        earliestCovidDateForeign => $earliestCovidDateForeign,
        currentLanguage   => $currentLanguage,
        languages         => \%languages,
        vaccinesChildren  => \%vaccinesChildren,
        vaccinesChildrenForeign  => \%vaccinesChildrenForeign
    );
}

1;