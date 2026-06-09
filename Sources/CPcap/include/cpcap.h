#ifndef CPCAP_H
#define CPCAP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Thin bridge over libpcap that keeps the pcap types out of Swift.
// A "handle" is an opaque pointer (a pcap_t* internally).

// Opens live capture on the given device (e.g. "en0").
// Returns a handle, or NULL on failure (errbuf is filled with the reason).
void *cpcap_open(const char *device, int snaplen, char *errbuf, int errbuf_len);

// Finds a sensible default device (first active non-loopback interface).
// Writes the name to buf. Returns 0 on success, -1 on failure.
int cpcap_default_device(char *buf, int buf_len, char *errbuf, int errbuf_len);

// Datalink type (DLT_*) for an open handle.
int cpcap_datalink(void *handle);

// Sets a BPF filter (e.g. "ip or ip6"). Returns 0 on success, -1 on failure.
int cpcap_set_filter(void *handle, const char *filter);

// Fetches the next packet (blocks until the timeout set in cpcap_open).
// Return: 1 = packet, 0 = timeout, -1 = error, -2 = EOF.
// On 1, *data points at the packet bytes (owned by pcap, valid until the next
// call) and *caplen is set to the number of captured bytes.
int cpcap_next(void *handle, const unsigned char **data, int *caplen);

void cpcap_close(void *handle);

#ifdef __cplusplus
}
#endif

#endif /* CPCAP_H */
