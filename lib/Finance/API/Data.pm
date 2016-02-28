package Finance::API::Data;
use Dancer2;

our $VERSION = '0.1';

use JSON::MaybeXS;
use Finance::HostedTrader::Datasource;
use Finance::HostedTrader::ExpressionParser;

get '/parse' => sub {
    my $db = Finance::HostedTrader::Datasource->new();
    my $cfg = $db->cfg;
    my $signal_processor = Finance::HostedTrader::ExpressionParser->new($db);

    my $timeframe  = query_parameters->get('t') || 'day';
    my $expr = 'datetime,'.query_parameters->get('e');
    my $symbols = (defined(query_parameters->get('s')) ? [ split( ',', query_parameters->get('s')) ] : $cfg->symbols->natural);
    my $jsonp_callback = query_parameters->get('jsoncallback');

    content_type 'application/json';

    my ($max_loaded_items, $max_display_items, $symbols_txt) = (1000, 1);
    my @results;
    foreach my $symbol (@{$symbols}) {
        my $data = $signal_processor->getIndicatorData({
                                    'fields' => $expr,
                                    'symbol' => $symbol,
                                    'tf'     => $timeframe,
                                    'maxLoadedItems' => $max_loaded_items,
                                    'numItems' => $max_display_items,
                                });
        next unless(defined($data));
        $data = $data->[0];
        next unless(defined($data));

        my %hash;
        $hash{symbol} = $symbol;
        for (my $i=0;$i<scalar(@$data);$i++) {
            $hash{"item$i"} = $data->[$i];
        }

        push @results, \%hash;
    }

    my $obj = {
        "ResultSet" => {
            "Total" => scalar(@results),
            "Result" => \@results,
        }
    };

    if ($jsonp_callback) {
        return $jsonp_callback . '(' . to_json($obj) . ')';
    } else {
        return to_json($obj);
    }

};

true;
