package Finance::API::Data;
use Dancer2;

our $VERSION = '0.1';

use JSON::MaybeXS;
use Finance::HostedTrader::Datasource;
use Finance::HostedTrader::Config;
use Finance::HostedTrader::ExpressionParser;
use Date::Manip;

get '/' => sub {

    return _generate_response(
        endpoints => [
            'http://api.fxhistoricaldata.com/v1/instruments',
            'http://api.fxhistoricaldata.com/v1/indicators',
            'http://api.fxhistoricaldata.com/v1/signals',
        ],
        links => {
            documentation => 'http://apidocs.fxhistoricaldata.com/',
            status => 'http://status.fxhistoricaldata.com/',
        },
    );
};

get '/instruments' => sub {
    my $cfg = Finance::HostedTrader::Config->new();

    my $instruments = $cfg->symbols->all();

    return _generate_response( results => $instruments );
};

get '/indicators' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $signal_processor = Finance::HostedTrader::ExpressionParser->new($db);

    my $timeframe  = query_parameters->get('timeframe') || 'day';
    my $expr = query_parameters->get('expression');
    my $instruments = (defined(query_parameters->get('instruments')) ? [ split( ',', query_parameters->get('instruments')) ] : []);
    my $max_display_items = query_parameters->get('itemcount') || 1;
    my $max_loaded_items = query_parameters->get('l') || 2000;

    content_type 'application/json';

    if (!$expr) {
        status 400;
        return _generate_response( id => "missing_expression", message => "The 'expression' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }

    if (!@$instruments) {
        status 400;
        return _generate_response( id => "missing_instrument", message => "The 'instruments' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }


    my %results;
    my $params = {
        'fields' => "datetime,".$expr,
        'tf'     => $timeframe,
        'maxLoadedItems' => $max_loaded_items,
        'numItems' => $max_display_items,
    };

    my %all_instruments = map { $_ => 1 } @{ $cfg->symbols->all() };
    foreach my $instrument (@{$instruments}) {
        if (!$all_instruments{$instrument}) {
            status 400;
            return _generate_response( id => "invalid_instrument", message => "instrument $instrument is not supported", url => "http://apidocs.fxhistoricaldata.com/#available-markets" );
        }
        $params->{symbol} = $instrument;
        my $indicator_result;
        eval {
            $indicator_result = $signal_processor->getIndicatorData($params);
            1;
        } || do {
            my $e = $@;
            status 500;

            if ( $e =~ /Syntax error/ ) {
                return _generate_response( id => "syntax_error", message => "Syntax error in expression '$expr'", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
            } else {
                return _generate_response( id => "internal_error", message => $e, url => "" );
            }
        };

        $results{$instrument} = $indicator_result;
    }
    delete $params->{symbol};

    my %return_obj = (
        params => $params,
        results => \%results,
    );

    return _generate_response(%return_obj);
};

get '/signals' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $signal_processor = Finance::HostedTrader::ExpressionParser->new($db);

    my $timeframe  = query_parameters->get('timeframe') || 'day';
    my $expr = query_parameters->get('expression');
    my $instruments = (defined(query_parameters->get('instruments')) ? [ split( ',', query_parameters->get('instruments')) ] : []);
    my $max_display_items = query_parameters->get('itemcount') || 1;
    my $max_loaded_items = query_parameters->get('l') || 2000;
    my $startPeriod = query_parameters->get('start_period') || '3 months ago';
    my $endPeriod = query_parameters->get('end_period') || 'now';

    content_type 'application/json';

    if (!$expr) {
        status 400;
        return _generate_response( id => "missing_expression", message => "The 'expression' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#signals" );
    }

    if (!@$instruments) {
        status 400;
        return _generate_response( id => "missing_instrument", message => "The 'instruments' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#signals" );
    }

    my $formattedStartPeriod    = UnixDate($startPeriod,    '%Y-%m-%d %H:%M:%S');
    if (!$formattedStartPeriod) {
        status 400;
        return _generate_response( id => "invalid_start_period", message => "The 'start_period' parameter value $startPeriod is not a valid date", url => "http://apidocs.fxhistoricaldata.com/#signals" );
    }

    my $formattedEndPeriod      = UnixDate($endPeriod,      '%Y-%m-%d %H:%M:%S');
    if (!$formattedEndPeriod) {
        status 400;
        return _generate_response( id => "invalid_end_period", message => "The 'end_period' parameter value $endPeriod is not a valid date", url => "http://apidocs.fxhistoricaldata.com/#signals" );
    }

    my %results;
    my $params = {
        'expr'          => $expr,
        'numItems'      => $max_display_items,
        'tf'            => $timeframe,
        'maxLoadedItems'=> $max_loaded_items,
        'startPeriod'   => $formattedStartPeriod,
        'endPeriod'     => $formattedEndPeriod,
    };

    my %all_instruments = map { $_ => 1 } @{ $cfg->symbols->all() };
    foreach my $instrument (@{$instruments}) {
        if (!$all_instruments{$instrument}) {
            status 400;
            return _generate_response( id => "invalid_instrument", message => "instrument $instrument is not supported", url => "http://apidocs.fxhistoricaldata.com/#available-markets" );
        }
        $params->{symbol} = $instrument;
        my $signal_result;
        eval {
            $signal_result = $signal_processor->getSignalData($params);
            1;
        } || do {
            my $e = $@;
            status 500;

            if ( $e =~ /Syntax error/ ) {
                return _generate_response( id => "syntax_error", message => "Syntax error in expression '$expr'", url => "http://apidocs.fxhistoricaldata.com/#signals" );
            } elsif ( $e =~ /In a multiple timeframe signal expression/ ) {
                return _generate_response( id => "multiple_timeframe_boolean_operators", message => "In a multiple timeframe signal expression, all boolean operators between timeframe functions need to be the same. This is a limitation of the API.", url => "http://apidocs.fxhistoricaldata.com/#multiple-timeframe-signals" );
            } else {
                return _generate_response( id => "internal_error", message => $e, url => "" );
            }
        };
        $results{$instrument} = $signal_result;
    }
    delete $params->{symbol};

    my %return_obj = (
        params => $params,
        results => \%results,
    );


    return _generate_response(%return_obj);

};

get '/lastclose' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $instruments  = query_parameters->get('instruments');

    $instruments = (defined($instruments) ? [ split( ',', $instruments) ] : $cfg->symbols->natural);

    content_type 'application/json';
    my $timeframe = 300;#TODO hardcoded lowest available timeframe is 5min. Could look it up in the config object ($db->cfg) instead.

    my %results;
    foreach my $instrument (@{$instruments}) {
        my @lastclose = $db->getLastClose( symbol => $instrument);
        $results{$instrument} = \@lastclose;
    }

    return _generate_response(%results);
};

any qr{.*} => sub {
    status 404;

    return _generate_response( id => "not_found",  message => "The requested resource does not exist", url => "http://apidocs.fxhistoricaldata.com/#api-reference" );
};

sub _generate_response {
    my %results = @_;
    my $jsonp_callback = query_parameters->get('jsoncallback');

    if ($jsonp_callback) {
        return $jsonp_callback . '(' . to_json(\%results) . ')';
    } else {
        return to_json(\%results);
    }
}

true;
