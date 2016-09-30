package Finance::API::Data;
use Dancer2;

our $VERSION = '0.1';

use JSON::MaybeXS;
use Finance::HostedTrader::Datasource;
use Finance::HostedTrader::ExpressionParser;
use Date::Manip;

get '/parse' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $signal_processor = Finance::HostedTrader::ExpressionParser->new($db);

    my $timeframe  = query_parameters->get('t') || 'day';
    my $expr = 'datetime,'.query_parameters->get('e');
    my $symbols = (defined(query_parameters->get('s')) ? [ split( ',', query_parameters->get('s')) ] : $cfg->symbols->natural);
    my $max_display_items = query_parameters->get('d') || 1;
    my $jsonp_callback = query_parameters->get('jsoncallback');
    my $max_loaded_items = query_parameters->get('l') || 1000;

    content_type 'application/json';

    my %results;
    foreach my $symbol (@{$symbols}) {
        my $data = $signal_processor->getIndicatorData({
                                    'fields' => $expr,
                                    'symbol' => $symbol,
                                    'tf'     => $timeframe,
                                    'maxLoadedItems' => $max_loaded_items,
                                    'numItems' => $max_display_items,
                                });
        next unless(defined($data));
        $results{$symbol} = $data;
    }


    if ($jsonp_callback) {
        return $jsonp_callback . '(' . to_json(\%results) . ')';
    } else {
        return to_json(\%results);
    }

};

get '/signal' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $signal_processor = Finance::HostedTrader::ExpressionParser->new($db);

    my $timeframe  = query_parameters->get('t') || 'day';
    my $expr = query_parameters->get('e');
    my $symbols = (defined(query_parameters->get('s')) ? [ split( ',', query_parameters->get('s')) ] : $cfg->symbols->natural);
    my $max_display_items = query_parameters->get('d') || 1;
    my $jsonp_callback = query_parameters->get('jsoncallback');
    my $max_loaded_items = query_parameters->get('l') || 1000;
    my $startPeriod = '90 days ago';
    my $endPeriod = 'now';

    content_type 'application/json';

    my %results;
    foreach my $symbol (@{$symbols}) {
        my $data = $signal_processor->getSignalData({
                                    'expr'          => $expr,
                                    'numItems'      => $max_display_items,
                                    'symbol'        => $symbol,
                                    'tf'            => $timeframe,
                                    'maxLoadedItems'=> $max_loaded_items,
                                    'startPeriod'   => UnixDate($startPeriod, '%Y-%m-%d %H:%M:%S'),
                                    'endPeriod'     => UnixDate($endPeriod, '%Y-%m-%d %H:%M:%S'),
                                });
        next unless(defined($data));
        $results{$symbol} = $data;
    }


    if ($jsonp_callback) {
        return $jsonp_callback . '(' . to_json(\%results) . ')';
    } else {
        return to_json(\%results);
    }



};

get '/lastclose' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $symbols  = query_parameters->get('s');

    $symbols = (defined($symbols) ? [ split( ',', $symbols) ] : $cfg->symbols->natural);
    my $jsonp_callback = query_parameters->get('jsoncallback');

    content_type 'application/json';
    my $timeframe = 300;#TODO hardcoded lowest available timeframe is 5min. Could look it up in the config object ($db->cfg) instead.

    my %results;
    foreach my $symbol (@{$symbols}) {
        my @lastclose = $db->getLastClose( symbol => $symbol);
        $results{$symbol} = \@lastclose;
    }

    if ($jsonp_callback) {
        return $jsonp_callback . '(' . to_json(\%results) . ')';
    } else {
        return to_json(\%results);
    }
};

true;
