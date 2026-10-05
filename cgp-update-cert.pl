#!/usr/bin/perl

use strict;
use warnings;
use FindBin; use lib $FindBin::Bin;
use MIME::Base64;
use CLI;

my $server   = '127.0.0.1'; # здесь прописываем адрес pwd сервера cgp для подключения
my $port     = 106; # порт pwd сервера cgp
my $domain   = 'mail.domain.com'; # домен, обслуживаемый cgp и обновляемый через certbot
my $username = 'postmaster'; # имя пользователя с правами на изменение настроек домена
my $password = 'mystrongpass'; # пароль этого пользователя

my $pkeyfile = "/etc/letsencrypt/live/$domain/privkey.pem";
my $certfile = "/etc/letsencrypt/live/$domain/cert.pem";
my $cafile   = "/etc/letsencrypt/live/$domain/chain.pem";

# Преобразуем закрытый ключ в формат DER+base64
my $pk = `openssl pkey -in $pkeyfile -outform DER 2>/dev/null | openssl base64 -e -A`;
die "Ошибка: Конвейер OpenSSL не смог сгенерировать строку ключа.\n" unless $pk;

# Получаем сертификат домена
open(CERT, $certfile) || die "Can't open $certfile: $!\n";
my $cert = join("", <CERT>); close CERT;
$cert =~ s/-----BEGIN CERTIFICATE-----//g;
$cert =~ s/-----END CERTIFICATE-----//g;
$cert =~ s/[\r\n\s]//g;

# Получаем цепочку CA и приводим ее к принимаемумому CGP формату в случае нескольких сертификатов
open(CA, $cafile) || die "Can't open $cafile: $!\n";
my $ca_content = join("", <CA>); close CA;
my @raw_certs = split(/-----BEGIN CERTIFICATE-----/, $ca_content);
shift @raw_certs; 
my $merged_binary_ca = "";

foreach my $cert_block (@raw_certs) {
    $cert_block =~ s/-----END CERTIFICATE-----.*//s;
    $cert_block =~ s/[\r\n\s]//g; 
    if ($cert_block) {
        $merged_binary_ca .= decode_base64($cert_block);
    }
}
my $ca_base64 = encode_base64($merged_binary_ca, "");
$ca_base64 =~ s/\s//g;
my $ca_list = "[" . $ca_base64 . "]";

# Оправляем сертификаты и ключ в CGP
my $cli = new CGP::CLI( { PeerAddr => $server, PeerPort => $port, login => $username, password => $password } )
    || die "Can't login to CGPro: ".$CGP::ERR_STRING."\n";

$cli->setDebug(1);

my $raw_cmd = "UpdateDomainSettings $domain { "
            . "CAChain = $ca_list; "
            . "PrivateSecureKey = [" . $pk . "]; "
            . "SecureCertificate = [" . $cert . "]; "
            . "}";

print "\n--- ОТПРАВКА СФОРМИРОВАННОЙ СТРОКИ В PWD-ПОРТ ---\n";
$cli->send($raw_cmd);

my $response = $cli->_parseResponse();
print "\nОТВЕТ СЕРВЕРА CGP: $response\n";

$cli->Logout;
