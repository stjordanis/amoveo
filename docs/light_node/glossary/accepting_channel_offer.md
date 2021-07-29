WARNING
========

this is an old expired version of the documentation.

Please use the new documentation instead. 

Here is the main page for the new documentation: https://github.com/zack-bitcoin/amoveo-docs 

And [here is the link for the newest version of the page you are currently looking at](https://github.com/zack-bitcoin/amoveo-docs/blob/master//light_node/glossary/accepting_channel_offer.md)

Accepting a Channel Offer
==========

Lets say that Bob made a bet on the outcome of a football game, and he posted it online. Now you want to accept the other side of the bet. What do you need to do?

Take the raw contract data that Bob posted online, and use the otc_listener.html page of the light node, for example it is hosted [here](http://159.89.87.58:8080/otc_listener.html)

When you copy/paste the raw contract data from Bob, or upload the file to otc_listener, it will allow you to view the details of the contract from inside the light node before you choose to accept. This way it is not possible for an attacker to trick you into accepting a contract that you did not want to accept.