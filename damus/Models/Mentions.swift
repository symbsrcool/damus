//
//  Mentions.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation

enum MentionType {
    case pubkey
    case event

    var ref: String {
        switch self {
        case .pubkey:
            return "p"
        case .event:
            return "e"
        }
    }
}

struct Mention: Equatable {
    let index: Int?
    let type: MentionType
    let ref: ReferencedId

    static func note(_ id: String) -> Mention {
        return Mention(index: nil, type: .event, ref: .e(id))
    }

    static func pubkey(_ pubkey: String) -> Mention {
        return Mention(index: nil, type: .pubkey, ref: .p(pubkey))
    }
}

typealias Invoice = LightningInvoice<Amount>
typealias ZapInvoice = LightningInvoice<Int64>

enum InvoiceDescription {
    case description(String)
    case description_hash(Data)
}

struct LightningInvoice<T> {
    let description: InvoiceDescription
    let amount: T
    let string: String
    let expiry: UInt64
    let payment_hash: Data
    let created_at: UInt64
    
    var description_string: String {
        switch description {
        case .description(let string):
            return string
        case .description_hash:
            return ""
        }
    }
}

enum Block: Equatable {
    static func == (lhs: Block, rhs: Block) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.mention(let a), .mention(let b)):
            return a == b
        case (.hashtag(let a), .hashtag(let b)):
            return a == b
        case (.url(let a), .url(let b)):
            return a == b
        case (.invoice(let a), .invoice(let b)):
            return a.string == b.string
        case (_, _):
            return false
        }
    }
    
    case text(String)
    case mention(Mention)
    case hashtag(String)
    case url(URL)
    case invoice(Invoice)
    case relay(String)
    
    var is_invoice: Invoice? {
        if case .invoice(let invoice) = self {
            return invoice
        }
        return nil
    }
    
    var is_hashtag: String? {
        if case .hashtag(let htag) = self {
            return htag
        }
        return nil
    }
    
    var is_url: URL? {
        if case .url(let url) = self {
            return url
        }
        
        return nil
    }
    
    var is_text: String? {
        if case .text(let txt) = self {
            return txt
        }
        return nil
    }
    
    var is_note_mention: Bool {
        guard case .mention(let mention) = self else {
            return false
        }
        
        return mention.type == .event
    }

    var is_mention: Mention? {
        if case .mention(let m) = self {
            return m
        }
        return nil
    }
}

func render_blocks(blocks: [Block]) -> String {
    return blocks.reduce("") { str, block in
        switch block {
        case .mention(let m):
            if let idx = m.index {
                return str + "#[\(idx)]"
            } else if m.type == .pubkey, let pk = bech32_pubkey(m.ref.ref_id) {
                return str + "nostr:\(pk)"
            } else if let note_id = bech32_note_id(m.ref.ref_id) {
                return str + "nostr:\(note_id)"
            } else {
                return str + m.ref.ref_id
            }
        case .relay(let relay):
            return str + relay
        case .text(let txt):
            return str + txt
        case .hashtag(let htag):
            return str + "#" + htag
        case .url(let url):
            return str + url.absoluteString
        case .invoice(let inv):
            return str + inv.string
        }
    }
}

struct Blocks: Equatable {
    let words: Int
    let blocks: [Block]
}

func parse_note_content(content: String, tags: [[String]]) -> Blocks {
    var out: [Block] = []
    
    var bs = note_blocks()
    bs.num_blocks = 0;
    
    blocks_init(&bs)
    
    let bytes = content.utf8CString
    let _ = bytes.withUnsafeBufferPointer { p in
        damus_parse_content(&bs, p.baseAddress)
    }
    
    var i = 0
    while (i < bs.num_blocks) {
        let block = bs.blocks[i]
        
        if let converted = convert_block(block, tags: tags) {
            out.append(converted)
        }
        
        i += 1
    }
    
    let words = Int(bs.words)
    blocks_free(&bs)
    
    return Blocks(words: words, blocks: out)
}

func strblock_to_string(_ s: str_block_t) -> String? {
    let len = s.end - s.start
    let bytes = Data(bytes: s.start, count: len)
    return String(bytes: bytes, encoding: .utf8)
}

func convert_block(_ b: block_t, tags: [[String]]) -> Block? {
    if b.type == BLOCK_HASHTAG {
        guard let str = strblock_to_string(b.block.str) else {
            return nil
        }
        return .hashtag(str)
    } else if b.type == BLOCK_TEXT {
        guard let str = strblock_to_string(b.block.str) else {
            return nil
        }
        return .text(str)
    } else if b.type == BLOCK_MENTION_INDEX {
        return convert_mention_index_block(ind: b.block.mention_index, tags: tags)
    } else if b.type == BLOCK_URL {
        return convert_url_block(b.block.str)
    } else if b.type == BLOCK_INVOICE {
        return convert_invoice_block(b.block.invoice)
    } else if b.type == BLOCK_MENTION_BECH32 {
        return convert_mention_bech32_block(b.block.mention_bech32)
    }

    return nil
}

func convert_url_block(_ b: str_block) -> Block? {
    guard let str = strblock_to_string(b) else {
        return nil
    }
    guard let url = URL(string: str) else {
        return .text(str)
    }
    return .url(url)
}

func maybe_pointee<T>(_ p: UnsafeMutablePointer<T>!) -> T? {
    guard p != nil else {
        return nil
    }
    return p.pointee
}

enum Amount: Equatable {
    case any
    case specific(Int64)
    
    func amount_sats_str() -> String {
        switch self {
        case .any:
            return NSLocalizedString("Any", comment: "Any amount of sats")
        case .specific(let amt):
            return format_msats(amt)
        }
    }
}

func format_msats_abbrev(_ msats: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.positiveSuffix = "m"
    formatter.positivePrefix = ""
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    formatter.roundingMode = .down
    formatter.roundingIncrement = 0.1
    formatter.multiplier = 1
    
    let sats = NSNumber(value: (Double(msats) / 1000.0))
    
    if msats >= 1_000_000*1000 {
        formatter.positiveSuffix = "m"
        formatter.multiplier = 0.000001
    } else if msats >= 1000*1000 {
        formatter.positiveSuffix = "k"
        formatter.multiplier = 0.001
    } else {
        return sats.stringValue
    }
    
    return formatter.string(from: sats) ?? sats.stringValue
}

func format_msats(_ msat: Int64, locale: Locale = Locale.current) -> String {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.minimumFractionDigits = 0
    numberFormatter.maximumFractionDigits = 3
    numberFormatter.roundingMode = .down
    numberFormatter.locale = locale

    let sats = NSNumber(value: (Double(msat) / 1000.0))
    let formattedSats = numberFormatter.string(from: sats) ?? sats.stringValue

    let format = localizedStringFormat(key: "sats_count", locale: locale)
    return String(format: format, locale: locale, sats.decimalValue as NSDecimalNumber, formattedSats)
}

func convert_invoice_block(_ b: invoice_block) -> Block? {
    guard let invstr = strblock_to_string(b.invstr) else {
        return nil
    }
    
    guard var b11 = maybe_pointee(b.bolt11) else {
        return nil
    }
    
    guard let description = convert_invoice_description(b11: b11) else {
        return nil
    }
    
    let amount: Amount = maybe_pointee(b11.msat).map { .specific(Int64($0.millisatoshis)) } ?? .any
    let payment_hash = Data(bytes: &b11.payment_hash, count: 32)
    let created_at = b11.timestamp
    
    tal_free(b.bolt11)
    return .invoice(Invoice(description: description, amount: amount, string: invstr, expiry: b11.expiry, payment_hash: payment_hash, created_at: created_at))
}

func convert_mention_bech32_block(_ b: mention_bech32_block) -> Block?
{
    switch b.bech32.type {
    case NOSTR_BECH32_NOTE:
        let note = b.bech32.data.note;
        let event_id = hex_encode(Data(bytes: note.event_id, count: 32))
        let event_id_ref = ReferencedId(ref_id: event_id, relay_id: nil, key: "e")
        return .mention(Mention(index: nil, type: .event, ref: event_id_ref))
        
    case NOSTR_BECH32_NEVENT:
        let nevent = b.bech32.data.nevent;
        let event_id = hex_encode(Data(bytes: nevent.event_id, count: 32))
        var relay_id: String? = nil
        if nevent.relays.num_relays > 0 {
            relay_id = strblock_to_string(nevent.relays.relays.0)
        }
        let event_id_ref = ReferencedId(ref_id: event_id, relay_id: relay_id, key: "e")
        return .mention(Mention(index: nil, type: .event, ref: event_id_ref))

    case NOSTR_BECH32_NPUB:
        let npub = b.bech32.data.npub
        let pubkey = hex_encode(Data(bytes: npub.pubkey, count: 32))
        let pubkey_ref = ReferencedId(ref_id: pubkey, relay_id: nil, key: "p")
        return .mention(Mention(index: nil, type: .pubkey, ref: pubkey_ref))

    case NOSTR_BECH32_NSEC:
        let nsec = b.bech32.data.nsec
        let nsec_bytes = Data(bytes: nsec.nsec, count: 32)
        let pubkey = privkey_to_pubkey_raw(sec: nsec_bytes.bytes) ?? hex_encode(nsec_bytes)
        return .mention(.pubkey(pubkey))

    case NOSTR_BECH32_NPROFILE:
        let nprofile = b.bech32.data.nprofile
        let pubkey = hex_encode(Data(bytes: nprofile.pubkey, count: 32))
        var relay_id: String? = nil
        if nprofile.relays.num_relays > 0 {
            relay_id = strblock_to_string(nprofile.relays.relays.0)
        }
        let pubkey_ref = ReferencedId(ref_id: pubkey, relay_id: relay_id, key: "p")
        return .mention(Mention(index: nil, type: .pubkey, ref: pubkey_ref))

    case NOSTR_BECH32_NRELAY:
        let nrelay = b.bech32.data.nrelay
        guard let relay_str = strblock_to_string(nrelay.relay) else {
            return nil
        }
        return .relay(relay_str)
        
    case NOSTR_BECH32_NADDR:
        // TODO: wtf do I do with this
        guard let naddr = strblock_to_string(b.str) else {
            return nil
        }
        return .text("nostr:" + naddr)

    default:
        return nil
    }
}

func convert_invoice_description(b11: bolt11) -> InvoiceDescription? {
    if let desc = b11.description {
        return .description(String(cString: desc))
    }
    
    if var deschash = maybe_pointee(b11.description_hash) {
        return .description_hash(Data(bytes: &deschash, count: 32))
    }
    
    return nil
}

func convert_mention_index_block(ind: Int32, tags: [[String]]) -> Block?
{
    let ind = Int(ind)
    
    if ind < 0 || (ind + 1 > tags.count) || tags[ind].count < 2 {
        return .text("#[\(ind)]")
    }
        
    let tag = tags[ind]
    guard let mention_type = parse_mention_type(tag[0]) else {
        return .text("#[\(ind)]")
    }
    
    guard let ref = tag_to_refid(tag) else {
        return .text("#[\(ind)]")
    }
    
    return .mention(Mention(index: ind, type: mention_type, ref: ref))
}

func find_tag_ref(type: String, id: String, tags: [[String]]) -> Int? {
    var i: Int = 0
    for tag in tags {
        if tag.count >= 2 {
            if tag[0] == type && tag[1] == id {
                return i
            }
        }
        i += 1
    }
    
    return nil
}

struct PostTags {
    let blocks: [Block]
    let tags: [[String]]
}

func parse_mention_type_ndb(_ tag: NdbTagElem) -> MentionType? {
    if tag.matches_char("e") {
        return .event
    } else if tag.matches_char("p") {
        return .pubkey
    }
    return nil
}

func parse_mention_type(_ c: String) -> MentionType? {
    if c == "e" {
        return .event
    } else if c == "p" {
        return .pubkey
    }
    
    return nil
}

/// Convert
func make_post_tags(post_blocks: [Block], tags: [[String]]) -> PostTags {
    var new_tags = tags

    for post_block in post_blocks {
        switch post_block {
        case .mention(let mention):
            let mention_type = mention.type
            if mention_type == .event {
                continue
            }

            new_tags.append(refid_to_tag(mention.ref))
        case .hashtag(let hashtag):
            new_tags.append(["t", hashtag.lowercased()])
        case .text: break
        case .invoice: break
        case .relay: break
        case .url(let url):
            new_tags.append(["r", url.absoluteString])
            break
        }
    }
    
    return PostTags(blocks: post_blocks, tags: new_tags)
}

func post_to_event(post: NostrPost, privkey: String, pubkey: String) -> NostrEvent {
    let tags = post.references.map(refid_to_tag) + post.tags
    let post_blocks = parse_post_blocks(content: post.content)
    let post_tags = make_post_tags(post_blocks: post_blocks, tags: tags)
    let content = render_blocks(blocks: post_tags.blocks)
    let new_ev = NostrEvent(content: content, pubkey: pubkey, kind: post.kind.rawValue, tags: post_tags.tags)
    new_ev.calculate_id()
    new_ev.sign(privkey: privkey)
    return new_ev
}

