#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Finance::API::Data;
Finance::API::Data->to_app;
