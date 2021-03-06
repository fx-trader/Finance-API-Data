package Finance::API::Data;
use Dancer2;

our $VERSION = '0.1';

use JSON::MaybeXS qw//;
use Finance::HostedTrader::Datasource;
use Finance::HostedTrader::Config;
use Finance::HostedTrader::ExpressionParser;
use Finance::HostedTrader::Provider;
use Date::Manip;
use MCE::Loop;

get '/' => sub {

    return _generate_response(
        endpoints => [
            'http://api.fxhistoricaldata.com/instruments',
            'http://api.fxhistoricaldata.com/timeframes',
            'http://api.fxhistoricaldata.com/indicators',
            'http://api.fxhistoricaldata.com/signals',
            'http://api.fxhistoricaldata.com/descriptivestatistics',
            'http://api.fxhistoricaldata.com/screener',
        ],
        links => {
            documentation => 'http://apidocs.fxhistoricaldata.com/',
            status => 'http://status.fxhistoricaldata.com/',
        },
    );
};

get '/instruments' => sub {
    my $cfg = Finance::HostedTrader::Config->new();
    my $provider = query_parameters->get('provider');

    my $data_provider = $cfg->provider($provider);
    my @instruments =$data_provider->getAllInstruments();

    return _generate_response( results => \@instruments );
};

get '/timeframes' => sub {
    my $cfg = Finance::HostedTrader::Config->new();

    my $timeframes = $cfg->timeframes->all_by_name();

    return _generate_response( results => $timeframes );
};

get '/indicators' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $signal_processor = Finance::HostedTrader::ExpressionParser->new($db);

    my $timeframe  = query_parameters->get('timeframe') || 'day';
    my $expr = query_parameters->get('expression');
    my $instruments = (defined(query_parameters->get('instruments')) ? [ split( ',', query_parameters->get('instruments')) ] : []);
    my $max_display_items = query_parameters->get('item_count') || 10;
    my $max_loaded_items = query_parameters->get('max_loaded_items') || 5000;
    my $start_period = query_parameters->get('start_period') || '3 years ago';
    my $end_period = query_parameters->get('end_period') || 'now';
    $max_loaded_items = $max_display_items if ($max_display_items > $max_loaded_items);
    my $provider = query_parameters->get('provider');

    if (!$expr) {
        status 400;
        return _generate_response( id => "missing_expression", message => "The 'expression' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }

    if (!@$instruments) {
        status 400;
        return _generate_response( id => "missing_instrument", message => "The 'instruments' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }

    my $formattedStartPeriod      = UnixDate($start_period,      '%Y-%m-%d %H:%M:%S');
    if (!$formattedStartPeriod) {
        status 400;
        return _generate_response( id => "invalid_start_period", message => "The 'start_period' parameter value $start_period is not a valid date", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }

    my $formattedEndPeriod      = UnixDate($end_period,      '%Y-%m-%d %H:%M:%S');
    if (!$formattedEndPeriod) {
        status 400;
        return _generate_response( id => "invalid_end_period", message => "The 'end_period' parameter value $end_period is not a valid date", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }

    my %all_timeframes = map { $_ => 1 } @{ $cfg->timeframes->all_by_name() };
    if (!$all_timeframes{$timeframe}) {
        status 400;
        return _generate_response( id => "invalid_timeframe", message => "The 'timeframe' parameter value $timeframe is not a valid timeframe", url => "http://api.fxhistoricaldata.com/timeframes" );
    }

    my %results;
    my $params = {
        'expression'        => "datetime,".$expr,
        'timeframe'         => $timeframe,
        'max_loaded_items'  => $max_loaded_items,
        'item_count'        => $max_display_items,
        'start_period'      => $formattedStartPeriod,
        'end_period'        => $formattedEndPeriod,
        'provider'          => $provider,
    };

    my $data_provider = $cfg->provider($provider);
    my %all_instruments = map { $_ => 1 } $data_provider->getAllInstruments();
    foreach my $instrument (@{$instruments}) {
        if (!$all_instruments{$instrument}) {
            status 400;
            return _generate_response( id => "invalid_instrument", message => "instrument $instrument is not supported", url => "http://apidocs.fxhistoricaldata.com/#available-markets" );
        }
        $params->{instrument} = $instrument;
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
    delete $params->{instrument};

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
    my $max_display_items = query_parameters->get('item_count') || 100;
    my $max_loaded_items = query_parameters->get('max_loaded_items') || 5000;
    $max_loaded_items = $max_display_items if ($max_display_items > $max_loaded_items);
    my $startPeriod = query_parameters->get('start_period') || '3 years ago';
    my $endPeriod = query_parameters->get('end_period') || 'now';
    my $provider = query_parameters->get('provider');

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

    my %all_timeframes = map { $_ => 1 } @{ $cfg->timeframes->all_by_name() };
    if (!$all_timeframes{$timeframe}) {
        status 400;
        return _generate_response( id => "invalid_timeframe", message => "The 'timeframe' parameter value $timeframe is not a valid timeframe", url => "http://api.fxhistoricaldata.com/timeframes" );
    }

    my %results;
    my $params = {
        'expression'        => $expr,
        'item_count'        => $max_display_items,
        'timeframe'         => $timeframe,
        'max_loaded_items'  => $max_loaded_items,
        'start_period'      => $formattedStartPeriod,
        'end_period'        => $formattedEndPeriod,
        'provider'          => $provider,
    };

    my $data_provider = $cfg->provider($provider);
    my %all_instruments = map { $_ => 1 } $data_provider->getAllInstruments();
    foreach my $instrument (@{$instruments}) {
        if (!$all_instruments{$instrument}) {
            status 400;
            return _generate_response( id => "invalid_instrument", message => "instrument $instrument is not supported", url => "http://apidocs.fxhistoricaldata.com/#available-markets" );
        }
        $params->{instrument} = $instrument;
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
    delete $params->{instrument};

    my %return_obj = (
        params => $params,
        results => \%results,
    );


    return _generate_response(%return_obj);

};

get '/signalsp' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;

    my $timeframe  = query_parameters->get('timeframe') || 'day';
    my $expr = query_parameters->get('expression');
    my $instruments = (defined(query_parameters->get('instruments')) ? [ split( ',', query_parameters->get('instruments')) ] : []);
    my $max_display_items = query_parameters->get('item_count') || 100;
    my $max_loaded_items = query_parameters->get('max_loaded_items') || 5000;
    $max_loaded_items = $max_display_items if ($max_display_items > $max_loaded_items);
    my $startPeriod = query_parameters->get('start_period') || '3 years ago';
    my $endPeriod = query_parameters->get('end_period') || 'now';
    my $provider = query_parameters->get('provider');

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

    my %all_timeframes = map { $_ => 1 } @{ $cfg->timeframes->all_by_name() };
    if (!$all_timeframes{$timeframe}) {
        status 400;
        return _generate_response( id => "invalid_timeframe", message => "The 'timeframe' parameter value $timeframe is not a valid timeframe", url => "http://api.fxhistoricaldata.com/timeframes" );
    }

    my $params = {
        'expression'        => $expr,
        'item_count'        => $max_display_items,
        'timeframe'         => $timeframe,
        'max_loaded_items'  => $max_loaded_items,
        'start_period'      => $formattedStartPeriod,
        'end_period'        => $formattedEndPeriod,
        'provider'          => $provider,
    };

    my $data_provider = $cfg->provider($provider);
    my %all_instruments = map { $_ => 1 } $data_provider->getAllInstruments();

    foreach my $instrument (@{$instruments}) {
        if (!$all_instruments{$instrument}) {
            status 400;
            return _generate_response( id => "invalid_instrument", message => "instrument $instrument is not supported", url => "http://apidocs.fxhistoricaldata.com/#available-markets" );
        }
    }

    my %results = mce_loop {
        my ($mce, $chunk_ref, $chunk_id) = @_;
        my %ret;
        my $signal_processor = Finance::HostedTrader::ExpressionParser->new();
        for my $instrument (@{ $chunk_ref }) {
            $params->{instrument} = $instrument;
            $ret{$instrument} = $signal_processor->getSignalData($params);
        }
        MCE->gather(%ret);

    } $instruments;

    delete $params->{instrument};

    my %return_obj = (
        params => $params,
        results => \%results,
    );


    return _generate_response(%return_obj);

};


get '/descriptivestatistics' => sub {
    my $db  = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $signal_processor = Finance::HostedTrader::ExpressionParser->new($db);

    my $percentiles         = query_parameters->get('percentiles') // '75,80,85,90,95,99';
    my $timeframe           = query_parameters->get('timeframe') // 'day';
    my $instruments         = (defined(query_parameters->get('instruments')) ? [ split( ',', query_parameters->get('instruments')) ] : []);
    my $max_display_items   = query_parameters->get('item_count') || 100;
    my $max_loaded_items    = query_parameters->get('max_loaded_items') || 5000;
    $max_loaded_items       = $max_display_items if ($max_display_items > $max_loaded_items);
    my $expr                = query_parameters->get('expression');
    my $provider = query_parameters->get('provider');
    my $inner_sql_filter = query_parameters->get('inner_sql_filter');

    if (!@$instruments) {
        status 400;
        return _generate_response( id => "missing_instrument", message => "The 'instruments' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }

    my %all_timeframes = map { $_ => 1 } @{ $cfg->timeframes->all_by_name() };
    if (!$all_timeframes{$timeframe}) {
        status 400;
        return _generate_response( id => "invalid_timeframe", message => "The 'timeframe' parameter value $timeframe is not a valid timeframe", url => "http://api.fxhistoricaldata.com/timeframes" );
    }

    my %results;
    my $params = {
        'expression'        => $expr,
        'percentiles'       => $percentiles,
        'timeframe'         => $timeframe,
        'max_loaded_items'  => $max_loaded_items,
        'item_count'        => $max_display_items,
        'provider'          => $provider,
        'inner_sql_filter'  => $inner_sql_filter,
    };

    my $data_provider = $cfg->provider($provider);
    my %all_instruments = map { $_ => 1 } $data_provider->getAllInstruments();

    foreach my $instrument (@{$instruments}) {
        if (!$all_instruments{$instrument}) {
            status 400;
            return _generate_response( id => "invalid_instrument", message => "instrument $instrument is not supported", url => "http://apidocs.fxhistoricaldata.com/#available-markets" );
        }
        $params->{instrument} = $instrument;
        my $result;
        eval {
            $result = $signal_processor->getDescriptiveStatisticsData($params);
            1;
        } || do {
            my $e = $@;
            status 500;

            return _generate_response( id => "internal_error", message => $e, url => "" );
        };

        $results{$instrument} = $result;
    }
    delete $params->{instrument};

    my %return_obj = (
        params  => $params,
        results => \%results,
    );

    return _generate_response(%return_obj);
};

get '/screener' => sub {
    header 'Access-Control-Allow-Origin' => 'http://fxhistoricaldata.com';
    my $cfg                 = Finance::HostedTrader::Config->new();
    my $signal_processor    = Finance::HostedTrader::ExpressionParser->new();

    my $timeframe   = query_parameters->get('timeframe') || 'day';
    my $expr        = query_parameters->get('expression');
    my $max_display_items   = 1;
    my $max_loaded_items    = query_parameters->get('max_loaded_items') || 5000;
    my $provider = query_parameters->get('provider');

    if (!$expr) {
        status 400;
        return _generate_response( id => "missing_expression", message => "The 'expression' parameter is missing", url => "http://apidocs.fxhistoricaldata.com/#indicators" );
    }

    my %all_timeframes = map { $_ => 1 } @{ $cfg->timeframes->all_by_name() };
    if (!$all_timeframes{$timeframe}) {
        status 400;
        return _generate_response( id => "invalid_timeframe", message => "The 'timeframe' parameter value $timeframe is not a valid timeframe", url => "http://api.fxhistoricaldata.com/timeframes" );
    }

    my %results;
    my @ordered_results;
    my $params = {
        'expression'        => "datetime,".$expr,
        'timeframe'         => $timeframe,
        'max_loaded_items'  => $max_loaded_items,
        'item_count'        => $max_display_items,
        'provider'          => $provider,
    };

    my @instruments         = $cfg->provider($provider)->getInstruments();
    foreach my $instrument (@instruments) {
        $params->{instrument} = $instrument;
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

        $results{$instrument} = $indicator_result->{data};
    }
    delete $params->{instrument};

    foreach my $instrument ( sort { $results{$b}->[0][1] <=> $results{$a}->[0][1] } keys %results) {
        push @ordered_results, [ $instrument, @{$results{$instrument}->[0]} ];
    }


    my %return_obj = (
        params  => $params,
        results => \@ordered_results,
    );

    return _generate_response(%return_obj);


};

get '/lastclose' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $instruments  = query_parameters->get('instruments');
    my $provider = query_parameters->get('provider');
    my $data_provider = $cfg->provider($provider);

    $instruments = (defined($instruments) ? [ split( ',', $instruments) ] : $data_provider->getInstruments);

    my $timeframe = 60;#TODO hardcoded lowest available timeframe is 5minute. Could look it up in the config object ($db->cfg) instead.

    my %results;
    foreach my $instrument (@{$instruments}) {
        my @lastclose = $db->getLastClose( instrument => $instrument, provider => $provider );
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
    my $format = query_parameters->get('format') || 'json';
    my $jsonp_callback = query_parameters->get('jsoncallback');

    if ($format eq 'csv') {
        content_type 'text/csv';
        my $instruments=query_parameters->get('instruments');
        $instruments =~ s/,/_/g;
        my $timeframe = query_parameters->get('timeframe');
        header 'Content-Disposition' => "inline; filename=fxhistoricaldata_${instruments}_${timeframe}.csv";

        my $buffer;
        foreach my $instrument (keys( %{$results{results}} )) {
            my $instrument_data = $results{results}->{$instrument}->{data};
            foreach my $row (@$instrument_data) {
                $buffer .= "$instrument," . join(",", @$row) . "\n";
            }
        }
        return $buffer;
    }

    content_type 'application/json';

    if ($jsonp_callback) {
        return $jsonp_callback . '(' . JSON::MaybeXS::to_json(\%results) . ')';
    } else {
        return JSON::MaybeXS::to_json(\%results);
    }
}

true;
