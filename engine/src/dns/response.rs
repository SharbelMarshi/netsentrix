//! Minimal DNS response scanning (compressed names, answer section).

const QTYPE_CNAME: u16 = 5;
const MAX_PTR_JUMPS: u8 = 32;

pub fn rcode(wire: &[u8]) -> Option<u8> {
    if wire.len() < 4 {
        return None;
    }
    Some(wire[3] & 0x0f)
}

fn norm_name(s: &str) -> String {
    s.trim().trim_end_matches('.').to_lowercase()
}

/// Read a domain name at `pos`; returns (name, byte position after the name).
pub fn read_wire_name(buf: &[u8], mut pos: usize) -> Option<(String, usize)> {
    let mut parts: Vec<String> = Vec::new();
    let mut jumps = 0u8;
    let mut trail_end: Option<usize> = None;

    loop {
        if pos >= buf.len() {
            return None;
        }
        let len = buf[pos] as usize;
        if len == 0 {
            pos += 1;
            let end = trail_end.unwrap_or(pos);
            return Some((parts.join("."), end));
        }
        if (len & 0xc0) == 0xc0 {
            if pos + 1 >= buf.len() {
                return None;
            }
            if jumps >= MAX_PTR_JUMPS {
                return None;
            }
            jumps += 1;
            if trail_end.is_none() {
                trail_end = Some(pos + 2);
            }
            let offset = ((len & 0x3f) << 8) | buf[pos + 1] as usize;
            pos = offset;
            continue;
        }
        if len > 63 || pos + 1 + len > buf.len() {
            return None;
        }
        pos += 1;
        let label = std::str::from_utf8(&buf[pos..pos + len]).ok()?;
        parts.push(label.to_ascii_lowercase());
        pos += len;
    }
}

fn skip_questions(buf: &[u8], mut pos: usize, qdcount: usize) -> Option<usize> {
    for _ in 0..qdcount {
        let (_, p) = read_wire_name(buf, pos)?;
        pos = p;
        if pos + 4 > buf.len() {
            return None;
        }
        pos += 4;
    }
    Some(pos)
}

fn iter_answer_rrs(
    wire: &[u8],
    mut f: impl FnMut(&str, u16, &[u8]) -> bool,
) -> Option<()> {
    if wire.len() < 12 {
        return None;
    }
    let qdcount = u16::from_be_bytes([wire[4], wire[5]]) as usize;
    let ancount = u16::from_be_bytes([wire[6], wire[7]]) as usize;
    let mut pos = skip_questions(wire, 12, qdcount)?;
    for _ in 0..ancount {
        let (owner, p0) = read_wire_name(wire, pos)?;
        pos = p0;
        if pos + 10 > wire.len() {
            return None;
        }
        let ty = u16::from_be_bytes([wire[pos], wire[pos + 1]]);
        let rdlen = u16::from_be_bytes([wire[pos + 8], wire[pos + 9]]) as usize;
        pos += 10;
        if pos + rdlen > wire.len() {
            return None;
        }
        let rdata = &wire[pos..pos + rdlen];
        if f(&owner, ty, rdata) {
            return Some(());
        }
        pos += rdlen;
    }
    Some(())
}

fn answer_type_for_owner(wire: &[u8], want_type: u16, owner_norm: &str) -> bool {
    let mut hit = false;
    let _ = iter_answer_rrs(wire, |o, ty, _| {
        if ty == want_type && norm_name(o) == owner_norm {
            hit = true;
            return true;
        }
        false
    });
    hit
}

fn cname_target_for_owner(wire: &[u8], owner_norm: &str) -> Option<String> {
    let mut out: Option<String> = None;
    let _ = iter_answer_rrs(wire, |o, ty, rdata| {
        if ty == QTYPE_CNAME && norm_name(o) == owner_norm {
            if let Some((target, _)) = read_wire_name(rdata, 0) {
                out = Some(target);
                return true;
            }
        }
        false
    });
    out
}

/// If we should issue another upstream query to follow CNAME (no direct answer yet).
pub fn cname_next_query_name(wire: &[u8], qname: &str, qtype: u16) -> Option<String> {
    use crate::dns::parser::{QTYPE_A, QTYPE_AAAA};
    if qtype != QTYPE_A && qtype != QTYPE_AAAA {
        return None;
    }
    if rcode(wire)? != 0 {
        return None;
    }
    let n = norm_name(qname);
    if answer_type_for_owner(wire, qtype, &n) {
        return None;
    }
    cname_target_for_owner(wire, &n)
}
