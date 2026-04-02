//! Minimal DNS wire parsing (single standard question, uncompressed QNAME in question).

#[derive(Debug, Clone)]
pub struct ParsedQuestion {
    pub id: u16,
    pub qname: String,
    pub qtype: u16,
    pub qclass: u16,
    /// Byte offset where the question section starts (usually 12).
    pub question_start: usize,
    /// End offset (exclusive), after QTYPE+QCLASS.
    pub question_end: usize,
}

/// `A` / `AAAA` / common meta; others forwarded without local block handling in MVP.
pub const QTYPE_A: u16 = 1;
pub const QTYPE_AAAA: u16 = 28;

pub fn parse_first_question(message: &[u8]) -> Option<ParsedQuestion> {
    if message.len() < 12 {
        return None;
    }
    let id = u16::from_be_bytes([message[0], message[1]]);
    let flags = u16::from_be_bytes([message[2], message[3]]);
    if (flags & 0x8000) != 0 {
        return None;
    }
    let qdcount = u16::from_be_bytes([message[4], message[5]]);
    if qdcount != 1 {
        return None;
    }

    let question_start = 12usize;
    let (qname, consumed) = read_qname_labels(message, question_start)?;
    let pos = question_start + consumed;
    if pos + 4 > message.len() {
        return None;
    }
    let qtype = u16::from_be_bytes([message[pos], message[pos + 1]]);
    let qclass = u16::from_be_bytes([message[pos + 2], message[pos + 3]]);
    let question_end = pos + 4;

    Some(ParsedQuestion {
        id,
        qname,
        qtype,
        qclass,
        question_start,
        question_end,
    })
}

fn read_qname_labels(buf: &[u8], mut pos: usize) -> Option<(String, usize)> {
    let start = pos;
    let mut parts: Vec<&str> = Vec::new();
    loop {
        if pos >= buf.len() {
            return None;
        }
        let len = buf[pos] as usize;
        if len == 0 {
            pos += 1;
            break;
        }
        if (buf[pos] & 0xC0) != 0 {
            // Compression: not supported in MVP parse path.
            return None;
        }
        if len > 63 || pos + 1 + len > buf.len() {
            return None;
        }
        pos += 1;
        let label = std::str::from_utf8(&buf[pos..pos + len]).ok()?;
        parts.push(label);
        pos += len;
    }
    let consumed = pos - start;
    Some((parts.join("."), consumed))
}
