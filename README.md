# IKEA Home Smart library
This library was written to control my IKEA Home Smart bulbs. After being
annoyed by the instability of HomeAssistant when controlling my lights, and
after making the shocking discovery that it calls out to an external tool for
each CoAP message it wants to send to your bulbs I wrote this little library. It
communicates with you bulbs via the IKEA Gateway through the CoAP protocol and
serialises the responses into practical objects you can use to build
applications. In my case it is used to automatically dim the lights up before my
alarm in the morning and down in the evenings. Apart from some stability issues
of the gateway itself it appears to be rock solid.

Based on the great work of @glenndehaan: https://github.com/glenndehaan/ikea-tradfri-coap-docs
as IKEA doesn't provide documentation for their CoAP interface (shame).
