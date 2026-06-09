#include "cpcap.h"

#include <pcap.h>
#include <string.h>
#include <stdlib.h>

static void copy_err(char *dst, int dst_len, const char *src) {
    if (dst && dst_len > 0) {
        strncpy(dst, src, dst_len - 1);
        dst[dst_len - 1] = '\0';
    }
}

void *cpcap_open(const char *device, int snaplen, char *errbuf, int errbuf_len) {
    char local_err[PCAP_ERRBUF_SIZE];
    local_err[0] = '\0';

    // promisc = 0: we only need the machine's own traffic.
    // to_ms = 200: the packet buffer is delivered at least every 200ms so that
    // cpcap_next returns regularly and lets us shut down cleanly.
    pcap_t *h = pcap_open_live(device, snaplen, 0, 200, local_err);
    if (h == NULL) {
        copy_err(errbuf, errbuf_len, local_err);
        return NULL;
    }
    return (void *)h;
}

int cpcap_default_device(char *buf, int buf_len, char *errbuf, int errbuf_len) {
    pcap_if_t *alldevs = NULL;
    char local_err[PCAP_ERRBUF_SIZE];

    if (pcap_findalldevs(&alldevs, local_err) == -1 || alldevs == NULL) {
        copy_err(errbuf, errbuf_len, local_err);
        return -1;
    }

    // Prefer the first device that is up and not loopback.
    pcap_if_t *chosen = alldevs;
    for (pcap_if_t *d = alldevs; d != NULL; d = d->next) {
        if (d->flags & PCAP_IF_LOOPBACK) continue;
        if (d->flags & PCAP_IF_UP) { chosen = d; break; }
    }

    copy_err(buf, buf_len, chosen->name);
    pcap_freealldevs(alldevs);
    return 0;
}

int cpcap_datalink(void *handle) {
    if (handle == NULL) return -1;
    return pcap_datalink((pcap_t *)handle);
}

int cpcap_set_filter(void *handle, const char *filter) {
    if (handle == NULL) return -1;
    pcap_t *h = (pcap_t *)handle;
    struct bpf_program prog;
    if (pcap_compile(h, &prog, filter, 1, PCAP_NETMASK_UNKNOWN) == -1) {
        return -1;
    }
    int r = pcap_setfilter(h, &prog);
    pcap_freecode(&prog);
    return r;
}

int cpcap_next(void *handle, const unsigned char **data, int *caplen) {
    if (handle == NULL) return -1;
    struct pcap_pkthdr *hdr = NULL;
    const u_char *pkt = NULL;
    int r = pcap_next_ex((pcap_t *)handle, &hdr, &pkt);
    if (r == 1) {
        if (data) *data = pkt;
        if (caplen) *caplen = (int)hdr->caplen;
    }
    return r;
}

void cpcap_close(void *handle) {
    if (handle != NULL) {
        pcap_close((pcap_t *)handle);
    }
}
