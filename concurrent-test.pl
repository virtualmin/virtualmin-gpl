#!/bin/bash

# Clean up first
./delete-domain.pl --domain clash1.com >/dev/null 2>&1
./delete-domain.pl --domain clash2.com >/dev/null 2>&1

(./create-domain.pl --domain clash1.com --dir --unix --web --dns --pass smeg --desc "Concurrent clash 1" --limits-from-template) &
(./create-domain.pl --domain clash2.com --dir --unix --web --dns --pass smeg --desc "Concurrent clash 2" --limits-from-template) &
wait
wait
echo "--------------------------------------------------------------------"
./validate-domains.pl --domain clash1.com --all-features
echo "--------------------------------------------------------------------"
./validate-domains.pl --domain clash2.com --all-features
echo "--------------------------------------------------------------------"
