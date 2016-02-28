package Finance::API::Data;
use Dancer2;

our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

true;
