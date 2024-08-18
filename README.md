# GBBS Pro Driver for Uthernet II

Assemble with Merlin32
Copy over to a ProDOS volume with Cadius.

To Install:

```
BLOAD ACOS.OBJ
BLOAD UTHERII,t$00,a$e00
BSAVE ACOS.OBJ,a$800,l$5300
```
Current status:
8/17/2024 - First working proof-of-concept. Wish it had autodetection and DHCP, but it's interesting that we have this much. Known bugs include timeout enforcement (guests get logged off pretty fast), the crlf translation, and currently I'm not making an effort to detect hangups. This is all not too hard to add.

Reference material:
https://docs.wiznet.io/img/products/w5100/W5100_DS_V128E.pdf

I will happily review and merge pull requests.
