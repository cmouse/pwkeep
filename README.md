PassWord Keep (pwkeep)
======================

Simple password storage system. 

Quick start guide
=================

Run pwkeep -i to initialize a new storage into ~/.pwkeep. This will create an RSA key pair.

If you want to tune the algorithm(s), key sizes and such, you can create ~/.pwkeep/config.yml (see below for syntax).

If you want to place it somewhere else, set PWKEEP\_HOME environment variable, or use -H (--home) parameter when running pwkeep. 

To add credentials, use

    pwkeep -c -n <name of cred>

To modify them

    pwkeep -e -n <name>

And to show

    pwkeep -v -n <name>

See --help for more options.

Features
========

Password keep is intended to be simple and easy to use. It uses RSA + AES256 encryption for your credentials. The
data is not restricted to usernames and passwords, you can store whatever you want.

Editing is done with embedded ruco text editor using memory-only backing. No temporary files are used. 

Configuration
=============

The configuration file is a simple YAML formatted file with following syntax (*NOT YET SUPPORTED*)

```yaml
---
  # less than 1k makes no sense. your files will be at least this / 8 bytes. 
  keysize: 2048 
  iterations: 2000
  # do not edit the following unless you know what you are doing. 
  cipher: AES-256-CTR
```

File formats
============

The private.pem file contains your private key. It is fully manipulatable with openssl binary without any specialities.

system-\* files contain actual credentials. The file name consists from system- prefix and hashed system name. The system
name is hashed iterations time with chosen hash, SHA512 by default.

The actual file format is:
 
  * header (encrypted with your public key)
    * nil terminated algorithm name
    * 16 byte iv (algorithm dependant)
    * 32 byte key (algorithm dependant)
  * data: encrypted credential with above key+id

You cannot decrypt this with openssl directly, but you can easily write a program to do this. The header is padded with OAEP 
padding. 
