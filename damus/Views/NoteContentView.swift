//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI
import LinkPresentation
import NaturalLanguage
import MarkdownUI

struct Blur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

struct NoteContentView: View {
    
    let damus_state: DamusState
    let event: NostrEvent
    @State var blur_images: Bool
    @State var load_media: Bool = false
    let size: EventViewKind
    let preview_height: CGFloat?
    let options: EventViewOptions

    @ObservedObject var artifacts_model: NoteArtifactsModel
    @ObservedObject var preview_model: PreviewModel
    @ObservedObject var settings: UserSettingsStore

    var note_artifacts: NoteArtifacts {
        return self.artifacts_model.state.artifacts ?? .separated(.just_content(event.get_content(damus_state.keypair)))
    }
    
    init(damus_state: DamusState, event: NostrEvent, blur_images: Bool, size: EventViewKind, options: EventViewOptions) {
        self.damus_state = damus_state
        self.event = event
        self.blur_images = blur_images
        self.size = size
        self.options = options
        self.preview_height = lookup_cached_preview_size(previews: damus_state.previews, evid: event.id)
        let cached = damus_state.events.get_cache_data(event.id)
        self._preview_model = ObservedObject(wrappedValue: cached.preview_model)
        self._artifacts_model = ObservedObject(wrappedValue: cached.artifacts_model)
        self._settings = ObservedObject(wrappedValue: damus_state.settings)
    }
    
    var truncate: Bool {
        return options.contains(.truncate_content)
    }
    
    var with_padding: Bool {
        return options.contains(.wide)
    }
    
    var preview: LinkViewRepresentable? {
        guard blur_images,
              case .loaded(let preview) = preview_model.state,
              case .value(let cached) = preview else {
            return nil
        }
        
        return LinkViewRepresentable(meta: .linkmeta(cached))
    }
    
    func truncatedText(content: CompatibleText) -> some View {
        Group {
            if truncate {
                TruncatedText(text: content)
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
            } else {
                content.text
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
            }
        }
    }
    
    func invoicesView(invoices: [Invoice]) -> some View {
        InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: invoices, settings: damus_state.settings)
    }

    var translateView: some View {
        TranslateView(damus_state: damus_state, event: event, size: self.size)
    }
    
    func previewView(links: [URL]) -> some View {
        Group {
            if let preview = self.preview, blur_images {
                if let preview_height {
                    preview
                        .frame(height: preview_height)
                } else {
                    preview
                }
            } else if let link = links.first {
                LinkViewRepresentable(meta: .url(link))
                    .frame(height: 50)
            }
        }
    }
    
    func MainContent(artifacts: NoteArtifactsSeparated) -> some View {
        VStack(alignment: .leading) {
            if size == .selected {
                if with_padding {
                    SelectableText(attributedString: artifacts.content.attributed, size: self.size)
                        .padding(.horizontal)
                } else {
                    SelectableText(attributedString: artifacts.content.attributed, size: self.size)
                }
            } else {
                if with_padding {
                    truncatedText(content: artifacts.content)
                        .padding(.horizontal)
                } else {
                    truncatedText(content: artifacts.content)
                }
            }

            if !options.contains(.no_translate) && (size == .selected || damus_state.settings.auto_translate) {
                if with_padding {
                    translateView
                        .padding(.horizontal)
                } else {
                    translateView
                }
            }

            if artifacts.media.count > 0 {
                if !damus_state.settings.media_previews && !load_media {
                    loadMediaButton(artifacts: artifacts)
                } else if !blur_images || (!blur_images && !damus_state.settings.media_previews && load_media) {
                    ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.media)
                } else if blur_images || (blur_images && !damus_state.settings.media_previews && load_media) {
                    ZStack {
                        ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.media)
                        Blur()
                            .onTapGesture {
                                blur_images = false
                            }
                    }
                }
            }
            
            if artifacts.invoices.count > 0 {
                if with_padding {
                    invoicesView(invoices: artifacts.invoices)
                        .padding(.horizontal)
                } else {
                    invoicesView(invoices: artifacts.invoices)
                }
            }
            
            if damus_state.settings.media_previews {
                if with_padding {
                    previewView(links: artifacts.links).padding(.horizontal)
                } else {
                    previewView(links: artifacts.links)
                }
            }
            
        }
    }
    
    func loadMediaButton(artifacts: NoteArtifactsSeparated) -> some View {
        Button(action: {
            load_media = true
        }, label: {
            VStack(alignment: .leading) {
                HStack {
                    Image("images")
                    Text("Load media", comment: "Button to show media in note.")
                        .fontWeight(.bold)
                        .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                }
                .padding(EdgeInsets(top: 5, leading: 10, bottom: 0, trailing: 10))
                
                ForEach(artifacts.media.indices, id: \.self) { index in
                    Divider()
                        .frame(height: 1)
                    switch artifacts.media[index] {
                    case .image(let url), .video(let url):
                        Text(url.absoluteString)
                            .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                            .foregroundStyle(DamusColors.neutral6)
                            .multilineTextAlignment(.leading)
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 5, trailing: 10))
                    }
                }
            }
            .background(DamusColors.neutral1)
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
        })
        .padding(.horizontal)
    }
    
    func load(force_artifacts: Bool = false) {
        // always reload artifacts on load
        let plan = get_preload_plan(evcache: damus_state.events, ev: event, our_keypair: damus_state.keypair, settings: damus_state.settings)
        
        // TODO: make this cleaner
        Task {
            // this is surprisingly slow
            let rel = format_relative_time(event.created_at)
            Task { @MainActor in
                self.damus_state.events.get_cache_data(event.id).relative_time.value = rel
            }
            
            if var plan {
                if force_artifacts {
                    plan.load_artifacts = true
                }
                await preload_event(plan: plan, state: damus_state)
            } else if force_artifacts {
                let arts = render_note_content(ev: event, profiles: damus_state.profiles, keypair: damus_state.keypair)
                self.artifacts_model.state = .loaded(arts)
            }
        }
    }
    
    func artifactPartsView(_ parts: [ArtifactPart]) -> some View {
        
        LazyVStack(alignment: .leading) {
            ForEach(parts.indices, id: \.self) { ind in
                let part = parts[ind]
                switch part {
                case .text(let txt):
                    if with_padding {
                        txt.padding(.horizontal)
                    } else {
                        txt
                    }
                case .invoice(let inv):
                    if with_padding {
                        InvoiceView(our_pubkey: damus_state.pubkey, invoice: inv, settings: damus_state.settings)
                            .padding(.horizontal)
                    } else {
                        InvoiceView(our_pubkey: damus_state.pubkey, invoice: inv, settings: damus_state.settings)
                    }
                case .media(let media):
                    Text(verbatim: "media \(media.url.absoluteString)")
                }
            }
        }
    }
    
    var ArtifactContent: some View {
        Group {
            switch self.note_artifacts {
            case .longform(let md):
                Markdown(md.markdown)
                    .padding([.leading, .trailing, .top])
            case .separated(let separated):
                MainContent(artifacts: separated)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var body: some View {
        ArtifactContent
            .onReceive(handle_notify(.profile_updated)) { profile in
                let blocks = event.blocks(damus_state.keypair)
                for block in blocks.blocks {
                    switch block {
                    case .mention(let m):
                        if case .pubkey(let pk) = m.ref, pk == profile.pubkey {
                            load(force_artifacts: true)
                            return
                        }
                    case .relay: return
                    case .text: return
                    case .hashtag: return
                    case .url: return
                    case .invoice: return
                    }
                }
            }
            .onAppear {
                load()
            }
    }
    
}

func attributed_string_attach_icon(_ astr: inout AttributedString, img: UIImage) {
    let attachment = NSTextAttachment()
    attachment.image = img
    let attachmentString = NSAttributedString(attachment: attachment)
    let wrapped = AttributedString(attachmentString)
    astr.append(wrapped)
}

func url_str(_ url: URL) -> CompatibleText {
    var attributedString = AttributedString(stringLiteral: url.absoluteString)
    attributedString.link = url
    attributedString.foregroundColor = DamusColors.purple
    
    return CompatibleText(attributed: attributedString)
 }

func mention_str(_ m: Mention<MentionRef>, profiles: Profiles) -> CompatibleText {
    switch m.ref {
    case .pubkey(let pk):
        let npub = bech32_pubkey(pk) 
        let profile_txn = profiles.lookup(id: pk)
        let profile = profile_txn.unsafeUnownedValue
        let disp = Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 50)
        var attributedString = AttributedString(stringLiteral: "@\(disp)")
        attributedString.link = URL(string: "damus:nostr:\(npub)")
        attributedString.foregroundColor = DamusColors.purple
        
        return CompatibleText(attributed: attributedString)
    case .note(let note_id):
        let bevid = bech32_note_id(note_id)
        var attributedString = AttributedString(stringLiteral: "@\(abbrev_pubkey(bevid))")
        attributedString.link = URL(string: "damus:nostr:\(bevid)")
        attributedString.foregroundColor = DamusColors.purple

        return CompatibleText(attributed: attributedString)
    }
}

struct LongformContent {
    let markdown: MarkdownContent
    let words: Int

    init(_ markdown: String) {
        let blocks = [BlockNode].init(markdown: markdown)
        self.markdown = MarkdownContent(blocks: blocks)
        self.words = count_markdown_words(blocks: blocks)
    }
}

enum NoteArtifacts {
    case separated(NoteArtifactsSeparated)
    case longform(LongformContent)

    var images: [URL] {
        switch self {
        case .separated(let arts):
            return arts.images
        case .longform:
            return []
        }
    }
}

enum ArtifactPart {
    case text(Text)
    case media(MediaUrl)
    case invoice(Invoice)
    
    var is_text: Bool {
        switch self {
        case .text:    return true
        case .media:   return false
        case .invoice: return false
        }
    }
}

class NoteArtifactsParts {
    var parts: [ArtifactPart]
    var words: Int
    
    init(parts: [ArtifactPart], words: Int) {
        self.parts = parts
        self.words = words
    }
}

struct NoteArtifactsSeparated: Equatable {
    static func == (lhs: NoteArtifactsSeparated, rhs: NoteArtifactsSeparated) -> Bool {
        return lhs.content == rhs.content
    }
    
    let content: CompatibleText
    let words: Int
    let urls: [UrlType]
    let invoices: [Invoice]
    
    var media: [MediaUrl] {
        return urls.compactMap { url in url.is_media }
    }
    
    var images: [URL] {
        return urls.compactMap { url in url.is_img }
    }
    
    var links: [URL] {
        return urls.compactMap { url in url.is_link }
    }
    
    static func just_content(_ content: String) -> NoteArtifactsSeparated {
        let txt = CompatibleText(attributed: AttributedString(stringLiteral: content))
        return NoteArtifactsSeparated(content: txt, words: 0, urls: [], invoices: [])
    }
}

enum NoteArtifactState {
    case not_loaded
    case loading
    case loaded(NoteArtifacts)
    
    var artifacts: NoteArtifacts? {
        if case .loaded(let artifacts) = self {
            return artifacts
        }
        
        return nil
    }
    
    var should_preload: Bool {
        switch self {
        case .loaded:
            return false
        case .loading:
            return false
        case .not_loaded:
            return true
        }
    }
}

func note_artifact_is_separated(kind: NostrKind?) -> Bool {
    return kind != .longform
}

func render_note_content(ev: NostrEvent, profiles: Profiles, keypair: Keypair) -> NoteArtifacts {
    let blocks = ev.blocks(keypair)

    if ev.known_kind == .longform {
        return .longform(LongformContent(ev.content))
    }
    
    return .separated(render_blocks(blocks: blocks, profiles: profiles))
}

fileprivate func artifact_part_last_text_ind(parts: [ArtifactPart]) -> (Int, Text)? {
    let ind = parts.count - 1
    if ind < 0 {
        return nil
    }
    
    guard case .text(let txt) = parts[safe: ind] else {
        return nil
    }
    
    return (ind, txt)
}

func reduce_text_block(blocks: [Block], ind: Int, txt: String, one_note_ref: Bool) -> String {
    var trimmed = txt
    
    if let prev = blocks[safe: ind-1],
       case .url(let u) = prev,
       classify_url(u).is_media != nil {
        trimmed = " " + trim_prefix(trimmed)
    }
    
    if let next = blocks[safe: ind+1] {
        if case .url(let u) = next, classify_url(u).is_media != nil {
            trimmed = trim_suffix(trimmed)
        } else if case .mention(let m) = next,
                  case .note = m.ref,
                  one_note_ref {
            trimmed = trim_suffix(trimmed)
        }
    }
    
    return trimmed
}

func render_blocks(blocks bs: Blocks, profiles: Profiles) -> NoteArtifactsSeparated {
    var invoices: [Invoice] = []
    var urls: [UrlType] = []
    let blocks = bs.blocks
    
    let one_note_ref = blocks
        .filter({
            if case .mention(let mention) = $0,
               case .note = mention.ref {
                return true
            }
            else {
                return false
            }
        })
        .count == 1
    
    var ind: Int = -1
    let txt: CompatibleText = blocks.reduce(CompatibleText()) { str, block in
        ind = ind + 1
        
        switch block {
        case .mention(let m):
            if case .note = m.ref, one_note_ref {
                return str
            }
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            return str + CompatibleText(stringLiteral: reduce_text_block(blocks: blocks, ind: ind, txt: txt, one_note_ref: one_note_ref))

        case .relay(let relay):
            return str + CompatibleText(stringLiteral: relay)
            
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        case .invoice(let invoice):
            invoices.append(invoice)
            return str
        case .url(let url):
            let url_type = classify_url(url)
            switch url_type {
            case .media:
                urls.append(url_type)
                return str
            case .link(let url):
                urls.append(url_type)
                return str + url_str(url)
            }
        }
    }

    return NoteArtifactsSeparated(content: txt, words: bs.words, urls: urls, invoices: invoices)
}

enum MediaUrl {
    case image(URL)
    case video(URL)
    
    var url: URL {
        switch self {
        case .image(let url):
            return url
        case .video(let url):
            return url
        }
    }
}

enum UrlType {
    case media(MediaUrl)
    case link(URL)
    
    var url: URL {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image(let url):
                return url
            case .video(let url):
                return url
            }
        case .link(let url):
            return url
        }
    }
    
    var is_video: URL? {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image:
                return nil
            case .video(let url):
                return url
            }
        case .link:
            return nil
        }
    }
    
    var is_img: URL? {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image(let url):
                return url
            case .video:
                return nil
            }
        case .link:
            return nil
        }
    }
    
    var is_link: URL? {
        switch self {
        case .media:
            return nil
        case .link(let url):
            return url
        }
    }
    
    var is_media: MediaUrl? {
        switch self {
        case .media(let murl):
            return murl
        case .link:
            return nil
        }
    }
}

func classify_url(_ url: URL) -> UrlType {
    let str = url.lastPathComponent.lowercased()
    
    if str.hasSuffix(".png") || str.hasSuffix(".jpg") || str.hasSuffix(".jpeg") || str.hasSuffix(".gif") || str.hasSuffix(".webp") {
        return .media(.image(url))
    }
    
    if str.hasSuffix(".mp4") || str.hasSuffix(".mov") || str.hasSuffix(".m3u8") {
        return .media(.video(url))
    }
    
    return .link(url)
}

func lookup_cached_preview_size(previews: PreviewCache, evid: NoteId) -> CGFloat? {
    guard case .value(let cached) = previews.lookup(evid) else {
        return nil
    }
    
    guard let height = cached.intrinsic_height else {
        return nil
    }
    
    return height
}

// trim suffix whitespace and newlines
func trim_suffix(_ str: String) -> String {
    return str.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
}

// trim prefix whitespace and newlines
func trim_prefix(_ str: String) -> String {
    return str.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
}

struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        let state2 = test_damus_state

        Group {
            VStack {
                NoteContentView(damus_state: state, event: test_note, blur_images: false, size: .normal, options: [])
            }
            .previewDisplayName("Short note")
            
            VStack {
                NoteContentView(damus_state: state, event: test_encoded_note_with_image!, blur_images: false, size: .normal, options: [])
            }
            .previewDisplayName("Note with image")

            VStack {
                NoteContentView(damus_state: state2, event: test_longform_event.event, blur_images: false, size: .normal, options: [.wide])
                    .border(Color.red)
            }
            .previewDisplayName("Long-form note")
        }
    }
}


func count_words(_ s: String) -> Int {
    return s.components(separatedBy: .whitespacesAndNewlines).count
}

func count_inline_nodes_words(nodes: [InlineNode]) -> Int {
    return nodes.reduce(0) { words, node in
        switch node {
        case .text(let words):
            return count_words(words)
        case .emphasis(let children):
            return words + count_inline_nodes_words(nodes: children)
        case .strong(let children):
            return words + count_inline_nodes_words(nodes: children)
        case .strikethrough(let children):
            return words + count_inline_nodes_words(nodes: children)
        case .softBreak, .lineBreak, .code, .html, .image, .link:
            return words
        }
    }
}

func count_markdown_words(blocks: [BlockNode]) -> Int {
    return blocks.reduce(0) { words, block in
        switch block {
        case .paragraph(let content):
            return words + count_inline_nodes_words(nodes: content)
        case .blockquote, .bulletedList, .numberedList, .taskList, .codeBlock, .htmlBlock, .heading, .table, .thematicBreak:
            return words
        }
    }
}

func separate_images(ev: NostrEvent, keypair: Keypair) -> [MediaUrl]? {
    let urlBlocks: [URL] = ev.blocks(keypair).blocks.reduce(into: []) { urls, block in
        guard case .url(let url) = block else {
            return
        }
        if classify_url(url).is_img != nil {
            urls.append(url)
        }
    }
    let mediaUrls = urlBlocks.map { MediaUrl.image($0) }
    return mediaUrls.isEmpty ? nil : mediaUrls
}

