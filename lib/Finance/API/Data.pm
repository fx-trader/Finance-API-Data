package Finance::API::Data;
use Dancer2;

our $VERSION = '0.1';

use JSON::MaybeXS;
use Finance::HostedTrader::Datasource;
use Finance::HostedTrader::ExpressionParser;
use Date::Manip;

get '/indicator' => sub {
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
    my $params = {
        'fields' => $expr,
        'tf'     => $timeframe,
        'maxLoadedItems' => $max_loaded_items,
        'numItems' => $max_display_items,
    };

    foreach my $symbol (@{$symbols}) {
        $params->{symbol} = $symbol;
        my $indicator_result = $signal_processor->getIndicatorData($params);
        $results{$symbol} = $indicator_result;
    }
    delete $params->{symbol};

    my $return_obj = {
        params => $params,
        results => \%results,
    };

    if ($jsonp_callback) {
        return $jsonp_callback . '(' . to_json($return_obj) . ')';
    } else {
        return to_json($return_obj);
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
    my $params = {
        'expr'          => $expr,
        'numItems'      => $max_display_items,
        'tf'            => $timeframe,
        'maxLoadedItems'=> $max_loaded_items,
        'startPeriod'   => UnixDate($startPeriod, '%Y-%m-%d %H:%M:%S'),
        'endPeriod'     => UnixDate($endPeriod, '%Y-%m-%d %H:%M:%S'),
    };

    foreach my $symbol (@{$symbols}) {
        $params->{symbol} = $symbol;
        my $signal_result = $signal_processor->getSignalData($params);
        $results{$symbol} = $signal_result;
    }
    delete $params->{symbol};

    my $return_obj = {
        params => $params,
        results => \%results,
    };


    if ($jsonp_callback) {
        return $jsonp_callback . '(' . to_json($return_obj) . ')';
    } else {
        return to_json($return_obj);
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
