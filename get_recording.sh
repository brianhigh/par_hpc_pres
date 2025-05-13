#!/bin/sh

fn='epi560_2025-05-13_hpc_pres_recording.mp4'
url='https://d2y36twrtb17ty.cloudfront.net/sessions/09504f30-4139-4431-93ee-b2dc01188fa8/842cd00c-38ca-426c-abc4-b2dc01188fda-921570ed-3e57-4931-ab03-b2dc012e4002.hls/451487/fragmented.mp4'

test -f "$fn" || (which wget && wget -O "$fn" "$url")
test -f "$fn" || (which curl && curl -o "$fn" "$url")
