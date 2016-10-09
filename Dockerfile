FROM fxtrader/finance-hostedtrader
MAINTAINER Joao Costa <joaocosta@zonalivre.org>

RUN cpanm --notest Dancer2

ADD . /webapp

EXPOSE 5000

CMD ["plackup", "/webapp/bin/app.psgi"]
