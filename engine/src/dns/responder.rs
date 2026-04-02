//! Build blocked DNS responses (sinkhole / NXDOMAIN).

use crate::config::schema::BlockPolicy;
use crate::dns::parser::{parse_first_question, ParsedQuestion, QTYPE_A, QTYPE_AAAA};

const TTL: u32 = 60;

/// Build a response for a blocked name. Returns `None` if we cannot synthesize (forward instead).
pub fn build_blocked_response(
    request: &[u8],
    pq: &ParsedQuestion,
    policy: BlockPolicy,
) -> Option<Vec<u8>> {
    match policy {
        BlockPolicy::NxDomain => Some(build_nxdomain(request, pq)),
        BlockPolicy::AZero => match pq.qtype {
            QTYPE_A => Some(build_a_sinkhole(request, pq)),
            QTYPE_AAAA => Some(build_aaaa_sinkhole(request, pq)),
            _ => None,
        },
    }
}

fn build_nxdomain(request: &[u8], pq: &ParsedQuestion) -> Vec<u8> {
    let mut out = Vec::with_capacity(pq.question_end + 12);
    out.extend_from_slice(&pq.id.to_be_bytes());
    // QR=1, standard query response, RA=1, RCODE=NXDOMAIN (3)
    out.extend_from_slice(&0x8183u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes()); // QDCOUNT
    out.extend_from_slice(&0u16.to_be_bytes()); // ANCOUNT
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&request[pq.question_start..pq.question_end]);
    out
}

fn build_a_sinkhole(request: &[u8], pq: &ParsedQuestion) -> Vec<u8> {
    let mut out = Vec::with_capacity(pq.question_end + 32);
    out.extend_from_slice(&pq.id.to_be_bytes());
    out.extend_from_slice(&0x8180u16.to_be_bytes()); // NOERROR + RA
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes()); // one answer
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&request[pq.question_start..pq.question_end]);
    // Answer: pointer to qname at offset 12
    out.extend_from_slice(&[0xC0, 0x0C]);
    out.extend_from_slice(&QTYPE_A.to_be_bytes());
    out.extend_from_slice(&pq.qclass.to_be_bytes());
    out.extend_from_slice(&TTL.to_be_bytes());
    out.extend_from_slice(&4u16.to_be_bytes()); // RDLENGTH
    out.extend_from_slice(&[0, 0, 0, 0]); // 0.0.0.0
    out
}

fn build_aaaa_sinkhole(request: &[u8], pq: &ParsedQuestion) -> Vec<u8> {
    let mut out = Vec::with_capacity(pq.question_end + 44);
    out.extend_from_slice(&pq.id.to_be_bytes());
    out.extend_from_slice(&0x8180u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&request[pq.question_start..pq.question_end]);
    out.extend_from_slice(&[0xC0, 0x0C]);
    out.extend_from_slice(&QTYPE_AAAA.to_be_bytes());
    out.extend_from_slice(&pq.qclass.to_be_bytes());
    out.extend_from_slice(&TTL.to_be_bytes());
    out.extend_from_slice(&16u16.to_be_bytes());
    out.extend_from_slice(&[0u8; 16]);
    out
}

/// SERVFAIL (RCODE 2) with the question section copied from the request.
pub fn build_servfail(request: &[u8]) -> Option<Vec<u8>> {
    let pq = parse_first_question(request)?;
    let end = pq.question_end;
    if end > request.len() {
        return None;
    }
    let mut out = Vec::with_capacity(end);
    out.extend_from_slice(&request[0..2]);
    out.push(request[2] | 0x80);
    out.push((request[3] & 0xf0) | 2);
    out.extend_from_slice(&request[4..12]);
    out.extend_from_slice(&request[12..end]);
    Some(out)
}
