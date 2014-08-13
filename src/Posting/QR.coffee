QR =
  init: ->
    return if !Conf['Quick Reply']

    @db = new DataBoard 'yourPosts'
    @posts = []

    if Conf['Hide Original Post Form']
      $.addClass doc, 'hide-original-post-form'

    $.on d, '4chanXInitFinished', @initReady

    Post.callbacks.push
      name: 'Quick Reply'
      cb:   @node

  initReady: ->
    $.off d, '4chanXInitFinished', QR.initReady
    QR.postingIsEnabled = !!$.id 'postForm'
    return unless QR.postingIsEnabled

    sc = $.el 'a',
      className: 'qr-shortcut fa fa-comment-o'
      title: 'Quick Reply'
      href: 'javascript:;'
    $.on sc, 'click', ->
      $.event 'CloseMenu'
      QR.open()
      QR.nodes.com.focus()
    Header.addShortcut sc, 2

    <% if (type === 'crx') { %>
    $.on d, 'paste',              QR.paste
    <% } %>
    $.on d, 'dragover',           QR.dragOver
    $.on d, 'drop',               QR.dropFile
    $.on d, 'dragstart dragend',  QR.drag
    switch g.VIEW
      when 'index'
        $.on d, 'IndexRefresh', QR.generatePostableThreadsList
      when 'thread'
        $.on d, 'ThreadUpdate', ->
          if g.DEAD
            QR.abort()
          else
            QR.status()

    return unless Conf['Persistent QR']
    QR.open()
    QR.hide() if Conf['Auto-Hide QR'] or g.VIEW is 'catalog' or g.VIEW is 'index' and Conf['Index Mode'] is 'catalog'

  node: ->
    if QR.db.get {boardID: @board.ID, threadID: @thread.ID, postID: @ID}
      $.addClass @nodes.root, 'your-post'
    $.on $('a[title="Reply to this post"]', @nodes.info), 'click', QR.quote

  persist: ->
    QR.open()
    QR.hide() if Conf['Auto-Hide QR']
  open: ->
    if QR.nodes
      QR.nodes.el.hidden = false
      QR.unhide()
      return
    try
      QR.dialog()
    catch err
      delete QR.nodes
      Main.handleErrors
        message: 'Quick Reply dialog creation crashed.'
        error: err
  close: ->
    if QR.req
      QR.abort()
      return
    QR.nodes.el.hidden = true
    QR.cleanNotifications()
    d.activeElement.blur()
    $.rmClass QR.nodes.el, 'dump'
    new QR.post true
    for post in QR.posts.splice 0, QR.posts.length - 1
      post.delete()
    QR.cooldown.auto = false
    QR.status()
  focusin: ->
    $.addClass QR.nodes.el, 'has-focus'
  focusout: ->
    <% if (type === 'crx') { %>
    $.rmClass QR.nodes.el, 'has-focus'
    <% } else { %>
    $.queueTask ->
      return if $.x 'ancestor::div[@id="qr"]', d.activeElement
      $.rmClass QR.nodes.el, 'has-focus'
    <% } %>
  hide: ->
    d.activeElement.blur()
    $.addClass QR.nodes.el, 'autohide'
    QR.nodes.autohide.checked = true
  unhide: ->
    $.rmClass QR.nodes.el, 'autohide'
    QR.nodes.autohide.checked = false
  toggleHide: ->
    if @checked
      QR.hide()
    else
      QR.unhide()
  toggleSage: ->
    {email} = QR.nodes
    email.value = !/sage/i.test(email.value) and 'sage' or ''

  error: (err) ->
    QR.open()
    if typeof err is 'string'
      el = $.tn err
    else
      el = err
      el.removeAttribute 'style'
    if QR.captcha.isEnabled and /captcha|verification/i.test el.textContent
      # Focus the captcha input on captcha error.
      QR.captcha.nodes.input.focus()
    notice = new Notice 'warning', el
    QR.notifications.push notice
    return unless Header.areNotificationsEnabled
    notif = new Notification 'Quick reply warning',
      body: el.textContent
      icon: Favicon.logo
    notif.onclick = -> window.focus()
    <% if (type === 'crx') { %>
    # Firefox automatically closes notifications
    # so we can't control the onclose properly.
    notif.onclose = -> notice.close()
    notif.onshow  = ->
      setTimeout ->
        notif.onclose = null
        notif.close()
      , 7 * $.SECOND
    <% } %>
  notifications: []
  cleanNotifications: ->
    for notification in QR.notifications
      notification.close()
    QR.notifications = []

  status: ->
    return unless QR.nodes
    {thread} = QR.posts[0]
    if thread isnt 'new' and g.threads["#{g.BOARD}.#{thread}"].isDead
      value    = 404
      disabled = true
      QR.cooldown.auto = false

    value = if QR.req
      QR.req.progress
    else
      QR.cooldown.seconds or value

    {status} = QR.nodes
    status.value = unless value
      'Submit'
    else if QR.cooldown.auto
      "Auto #{value}"
    else
      value
    status.disabled = disabled or false

  quote: (e) ->
    e?.preventDefault()
    return unless QR.postingIsEnabled

    sel  = d.getSelection()
    post = Get.postFromNode @
    text = ">>#{post}\n"
    if sel.toString().trim() and post is Get.postFromNode sel.anchorNode
      range = sel.getRangeAt 0
      frag  = range.cloneContents()
      ancestor = range.commonAncestorContainer
      if ancestor.nodeName is '#text'
        # Quoting the insides of a spoiler/code tag.
        if $.x 'ancestor::s', ancestor
          $.prepend frag, $.tn '[spoiler]'
          $.add     frag, $.tn '[/spoiler]'
        if $.x 'ancestor::pre[contains(@class,"prettyprint")]', ancestor
          $.prepend frag, $.tn '[code]'
          $.add     frag, $.tn '[/code]'
      for node in $$ 'br', frag
        $.replace node, $.tn '\n>' unless node is frag.lastChild
      for node in $$ 's', frag
        $.replace node, [$.tn('[spoiler]'), node.childNodes..., $.tn '[/spoiler]']
      for node in $$ '.prettyprint', frag
        $.replace node, [$.tn('[code]'), node.childNodes..., $.tn '[/code]']
      text += ">#{frag.textContent.trim()}\n"

    QR.open()
    if QR.selected.isLocked
      index = QR.posts.indexOf QR.selected
      (QR.posts[index+1] or new QR.post()).select()
      $.addClass QR.nodes.el, 'dump'
      QR.cooldown.auto = true
    {com, thread} = QR.nodes
    thread.value = Get.threadFromNode @ unless com.value

    caretPos = com.selectionStart
    # Replace selection for text.
    com.value = com.value[...caretPos] + text + com.value[com.selectionEnd..]
    # Move the caret to the end of the new quote.
    range = caretPos + text.length
    com.setSelectionRange range, range
    com.focus()

    QR.selected.save com
    QR.selected.save thread

  characterCount: ->
    counter = QR.nodes.charCount
    count   = QR.nodes.com.textLength
    counter.textContent = count
    counter.hidden      = count < 1000
    (if count > 1500 then $.addClass else $.rmClass) counter, 'warning'

  drag: (e) ->
    # Let it drag anything from the page.
    toggle = if e.type is 'dragstart' then $.off else $.on
    toggle d, 'dragover', QR.dragOver
    toggle d, 'drop',     QR.dropFile
  dragOver: (e) ->
    e.preventDefault()
    e.dataTransfer.dropEffect = 'copy' # cursor feedback
  dropFile: (e) ->
    # Let it only handle files from the desktop.
    return unless e.dataTransfer.files.length
    e.preventDefault()
    QR.open()
    QR.handleFiles e.dataTransfer.files
  paste: (e) ->
    files = []
    for item in e.clipboardData.items when item.kind is 'file'
      blob = item.getAsFile()
      blob.name  = 'file'
      blob.name += '.' + blob.type.split('/')[1] if blob.type
      files.push blob
    return unless files.length
    QR.open()
    QR.handleFiles files
    $.addClass QR.nodes.el, 'dump'
  handleBlob: (urlBlob, header, url) ->
    name = url.substr url.lastIndexOf('/')+1, url.length
    start = header.indexOf("Content-Type: ") + 14
    endsc = header.substr(start, header.length).indexOf ';'
    endnl = header.substr(start, header.length).indexOf('\n') - 1
    end = endnl
    if endsc isnt -1 and endsc < endnl
      end = endsc
    mime = header.substr start, end
    blob = new Blob [urlBlob], {type: mime}
    blob.name = url.substr url.lastIndexOf('/') + 1, url.length
    name_start = header.indexOf('name="') + 6
    if name_start - 6 isnt -1
      name_end = header.substr(name_start, header.length).indexOf '"'
      blob.name = header.substr name_start, name_end

    return if blob.type is null
      QR.error 'Unsupported file type.'
    return unless blob.type in ['image/jpeg', 'image/png', 'image/gif', 'application/pdf', 'application/x-shockwave-flash', '']
      QR.error 'Unsupported file type.'
    QR.handleFiles [blob]

  handleUrl: ->
    url = prompt 'Insert an url:'
    return if url is null
    <% if (type === 'crx') { %>
    xhr = new XMLHttpRequest();
    xhr.open 'GET', url, true
    xhr.responseType = 'blob'
    xhr.onload = (e) ->
      if @readyState is @DONE && xhr.status is 200
        QR.handleBlob @response, @getResponseHeader('Content-Type'), url
        return
      else
        QR.error 'Can\'t load image.'
        return
    xhr.onerror = (e) ->
      QR.error 'Can\'t load image.'
      return
    xhr.send()
    return
    <% } %>

    <% if (type === 'userscript') { %>
    GM_xmlhttpRequest {
      method: "GET",
      url: url,
      overrideMimeType: 'text/plain; charset=x-user-defined',
      onload: (xhr) ->
        r = xhr.responseText
        data = new Uint8Array r.length
        i = 0
        while i < r.length
          data[i] = r.charCodeAt i
          i++
        QR.handleBlob data, xhr.responseHeaders, url
        return
        onerror: (xhr) ->
          QR.error "Can't load image."
    }
    return
    <% } %>
  handleFiles: (files) ->
    if @ isnt QR # file input
      files  = [@files...]
      @value = null
    return unless files.length
    max = QR.nodes.fileInput.max
    isSingle = files.length is 1
    QR.cleanNotifications()
    for file in files
      QR.handleFile file, isSingle, max
    $.addClass QR.nodes.el, 'dump' unless isSingle
  handleFile: (file, isSingle, max) ->
    if file.size > max
      QR.error "#{file.name}: File too large (file: #{$.bytesToString file.size}, max: #{$.bytesToString max})."
      return
    if isSingle
      post = QR.selected
    else if (post = QR.posts[QR.posts.length - 1]).file
      post = new QR.post()
    if /^text/.test file.type
      post.pasteText file
    else
      post.setFile file
  openFileInput: ->
    QR.nodes.fileInput.click()

  generatePostableThreadsList: ->
    return unless QR.nodes
    list    = QR.nodes.thread
    options = [list.firstChild]
    for thread of g.BOARD.threads
      options.push $.el 'option',
        value: thread
        textContent: "Thread No.#{thread}"
    val = list.value
    $.rmAll list
    $.add list, options
    list.value = val
    return unless list.value
    # Fix the value if the option disappeared.
    list.value = if g.VIEW is 'thread'
      g.THREADID
    else
      'new'

  dialog: ->
    dialog = UI.dialog 'qr', 'top:0;right:0;', <%= importHTML('Posting/QR') %>

    QR.nodes = nodes =
      el:         dialog
      move:       $ '.move',             dialog
      autohide:   $ '#autohide',         dialog
      thread:     $ 'select',            dialog
      close:      $ '.close',            dialog
      form:       $ 'form',              dialog
      dumpButton: $ '#dump-button',      dialog
      urlButton:  $ '#url-button',       dialog
      name:       $ '[data-name=name]',  dialog
      email:      $ '[data-name=email]', dialog
      sub:        $ '[data-name=sub]',   dialog
      com:        $ '[data-name=com]',   dialog
      dumpList:   $ '#dump-list',        dialog
      proceed:    $ '[name=qr-proceed]', dialog
      addPost:    $ '#add-post',         dialog
      charCount:  $ '#char-count',       dialog
      fileSubmit: $ '#file-n-submit',    dialog
      fileButton: $ '#qr-file-button',   dialog
      filename:   $ '#qr-filename',      dialog
      filesize:   $ '#qr-filesize',      dialog
      fileRM:     $ '#qr-filerm',        dialog
      spoiler:    $ '#qr-file-spoiler',  dialog
      status:     $ '[type=submit]',     dialog
      fileInput:  $ '[type=file]',       dialog

    if Conf['Tab to Choose Files First']
      $.add nodes.fileSubmit, nodes.status

    $.get 'qr-proceed', false, (item) ->
      nodes.proceed.checked = item['qr-proceed']
    nodes.fileInput.max = $('input[name=MAX_FILE_SIZE]').value

    QR.spoiler = !!$ 'input[name=spoiler]'
    nodes.spoiler.hidden = !QR.spoiler

    if g.BOARD.ID is 'f'
      nodes.flashTag = $.el 'select',
        name: 'filetag'
        innerHTML: """
          <option value=0>Hentai</option>
          <option value=6>Porn</option>
          <option value=1>Japanese</option>
          <option value=2>Anime</option>
          <option value=3>Game</option>
          <option value=5>Loop</option>
          <option value=4 selected>Other</option>
        """
      nodes.flashTag.dataset.default = '4'
      $.add nodes.form, nodes.flashTag
    if flagSelector = $ '.flagSelector'
      nodes.flag = flagSelector.cloneNode true
      nodes.flag.dataset.name    = 'flag'
      nodes.flag.dataset.default = '0'
      $.add nodes.form, nodes.flag

    <% if (type === 'userscript') { %>
    # XXX Firefox lacks focusin/focusout support.
    for elm in $$ '*', QR.nodes.el
      $.on elm, 'blur',  QR.focusout
      $.on elm, 'focus', QR.focusin
    <% } %>
    $.on dialog, 'focusin',  QR.focusin
    $.on dialog, 'focusout', QR.focusout
    $.on nodes.fileButton, 'click',  QR.openFileInput
    $.on nodes.autohide,   'change', QR.toggleHide
    $.on nodes.close,      'click',  QR.close
    $.on nodes.dumpButton, 'click',  -> nodes.el.classList.toggle 'dump'
    $.on nodes.urlButton,  'click',  QR.handleUrl
    $.on nodes.proceed,    'click',  $.cb.checked
    $.on nodes.addPost,    'click',  -> new QR.post true
    $.on nodes.form,       'submit', QR.submit
    $.on nodes.fileRM,     'click',  -> QR.selected.rmFile()
    $.on nodes.spoiler,    'change', -> QR.selected.nodes.spoiler.click()
    $.on nodes.fileInput,  'change', QR.handleFiles
    # save selected post's data
    save = -> QR.selected.save @
    for name in ['thread', 'name', 'email', 'sub', 'com', 'filename', 'flag']
      continue unless node = nodes[name]
      event = if node.nodeName is 'SELECT' then 'change' else 'input'
      $.on nodes[name], event, save

    <% if (type === 'userscript') { %>
    if Conf['Remember QR Size']
      $.get 'QR Size', '', (item) ->
        nodes.com.style.cssText = item['QR Size']
      $.on nodes.com, 'mouseup', (e) ->
        return if e.button isnt 0
        $.set 'QR Size', @style.cssText
    <% } %>

    QR.generatePostableThreadsList()
    QR.persona.init()
    new QR.post true
    QR.status()
    QR.cooldown.init()
    QR.captcha.init()
    $.add d.body, dialog

    # Create a custom event when the QR dialog is first initialized.
    # Use it to extend the QR's functionalities, or for XTRM RICE.
    $.event 'QRDialogCreation', null, dialog

  submit: (e) ->
    e?.preventDefault()

    if QR.req
      QR.abort()
      return

    if QR.cooldown.seconds
      QR.cooldown.auto = !QR.cooldown.auto
      QR.status()
      return

    post = QR.posts[0]
    post.forceSave()
    if g.BOARD.ID is 'f'
      filetag = QR.nodes.flashTag.value
    threadID = post.thread
    thread = g.BOARD.threads[threadID]

    # prevent errors
    if threadID is 'new'
      threadID = null
      if g.BOARD.ID is 'vg' and !post.sub
        err = 'New threads require a subject.'
      else unless post.file or textOnly = !!$ 'input[name=textonly]', $.id 'postForm'
        err = 'No file selected.'
    else if g.BOARD.threads[threadID].isClosed
      err = 'You can\'t reply to this thread anymore.'
    else unless post.com or post.file
      err = 'No file selected.'
    else if post.file and thread.fileLimit
      err = 'Max limit of image replies has been reached.'
    else if !post.file and /pic(ture)? related/i.test post.com
      err = 'No file selected despite your post mentioning one.'
    else for hook in QR.preSubmitHooks
      if err = hook post, thread
        break

    if QR.captcha.isEnabled and !err
      {challenge, response} = QR.captcha.getOne()
      err = 'No valid captcha.' unless response

    QR.cleanNotifications()
    if err
      # stop auto-posting
      QR.cooldown.auto = false
      QR.status()
      QR.error err
      return

    # Enable auto-posting if we have stuff to post, disable it otherwise.
    QR.cooldown.auto = QR.posts.length > 1
    if Conf['Auto-Hide QR'] and !QR.cooldown.auto
      QR.hide()
    if !QR.cooldown.auto and $.x 'ancestor::div[@id="qr"]', d.activeElement
      # Unfocus the focused element if it is one within the QR and we're not auto-posting.
      d.activeElement.blur()

    com = if Conf['Markdown'] then Markdown.format post.com else post.com

    post.lock()

    formData =
      resto:    threadID
      name:     post.name
      email:    post.email
      sub:      post.sub
      com:      com
      upfile:   post.file
      filetag:  filetag
      spoiler:  post.spoiler
      flag:     post.flag
      textonly: textOnly
      mode:     'regist'
      pwd:      QR.persona.pwd
      recaptcha_challenge_field: challenge
      recaptcha_response_field:  response

    options =
      responseType: 'document'
      withCredentials: true
      onload: QR.response
      onerror: ->
        # Connection error, or
        # www.4chan.org/banned
        delete QR.req
        if QR.captcha.isEnabled
          QR.captcha.destroy()
          QR.captcha.setup()
        post.unlock()
        QR.cooldown.auto = false
        QR.status()
        QR.error $.el 'span',
          innerHTML: """
          Connection error. You may have been <a href=//www.4chan.org/banned target=_blank>banned</a>.
          [<a href="https://github.com/MayhemYDG/4chan-x/wiki/FAQ#what-does-connection-error-you-may-have-been-banned-mean" target=_blank>FAQ</a>]
          """
    extra =
      form: $.formData formData
      upCallbacks:
        onload: ->
          # Upload done, waiting for server response.
          QR.req.isUploadFinished = true
          QR.req.uploadEndTime    = Date.now()
          QR.req.progress = '...'
          QR.status()
        onprogress: (e) ->
          # Uploading...
          QR.req.progress = "#{Math.round e.loaded / e.total * 100}%"
          QR.status()

    QR.req = $.ajax $.id('postForm').parentNode.action, options, extra
    # Starting to upload might take some time.
    # Provide some feedback that we're starting to submit.
    QR.req.uploadStartTime = Date.now()
    QR.req.progress = '...'
    QR.status()

  response: ->
    {req} = QR
    delete QR.req

    QR.captcha.destroy() if QR.captcha.isEnabled
    post = QR.posts[0]
    postsCount = QR.posts.length - 1
    post.unlock()

    resDoc  = req.response
    if ban  = $ '.banType', resDoc # banned/warning
      board = $('.board', resDoc).innerHTML
      err   = $.el 'span', innerHTML:
        if ban.textContent.toLowerCase() is 'banned'
          """
          You are banned on #{board}! ;_;<br>
          Click <a href=//www.4chan.org/banned target=_blank>here</a> to see the reason.
          """
        else
          """
          You were issued a warning on #{board} as #{$('.nameBlock', resDoc).innerHTML}.<br>
          Reason: #{$('.reason', resDoc).innerHTML}
          """
    else if err = resDoc.getElementById 'errmsg' # error!
      $('a', err)?.target = '_blank' # duplicate image link
    else if resDoc.title isnt 'Post successful!'
      err = 'Connection error with sys.4chan.org.'
    else if req.status isnt 200
      err = "Error #{req.statusText} (#{req.status})"

    if err
      if /captcha|verification/i.test(err.textContent) or err is 'Connection error with sys.4chan.org.'
        # Remove the obnoxious 4chan Pass ad.
        if /mistyped/i.test err.textContent
          err = 'You seem to have mistyped the CAPTCHA.'
        QR.cooldown.auto = false
        # Too many frequent mistyped captchas will auto-ban you!
        # On connection error, the post most likely didn't go through.
        QR.cooldown.set delay: 2
      else if err.textContent and m = err.textContent.match /wait(?:\s+(\d+)\s+minutes)?\s+(\d+)\s+second/i
        QR.cooldown.auto = !QR.captcha.isEnabled
        QR.cooldown.set delay: (m[1] or 0) * 60 + Number m[2]
      else if err.textContent.match /duplicate\sfile/i
        if QR.nodes.proceed.checked and postsCount
          post.rm()
          QR.cooldown.auto = true
          QR.cooldown.set delay: 10
        else
          QR.cooldown.auto = false
      else # stop auto-posting
        QR.cooldown.auto = false
      QR.status()
      QR.error err
      QR.captcha.setup() if QR.captcha.isEnabled
      return

    h1 = $ 'h1', resDoc
    QR.cleanNotifications()
    QR.notifications.push new Notice 'success', h1.textContent, 5

    QR.persona.set post

    [_, threadID, postID] = h1.nextSibling.textContent.match /thread:(\d+),no:(\d+)/
    postID   = +postID
    threadID = +threadID or postID
    isReply  = threadID isnt postID

    QR.db.set
      boardID: g.BOARD.ID
      threadID: threadID
      postID: postID
      val: true

    # Post/upload confirmed as successful.
    $.event 'QRPostSuccessful', {
      boardID: g.BOARD.ID
      threadID
      postID
    }
    $.event 'QRPostSuccessful_', {boardID: g.BOARD.ID, threadID, postID}

    # Enable auto-posting if we have stuff left to post, disable it otherwise.
    QR.cooldown.auto = postsCount and isReply
    QR.captcha.setup() if QR.captcha.isEnabled and QR.cooldown.auto

    unless Conf['Persistent QR'] or QR.cooldown.auto
      QR.close()
    else
      post.rm()

    QR.cooldown.set {req, post, isReply, threadID}

    URL = if threadID is postID # new thread
      Build.path g.BOARD.ID, threadID
    else if g.VIEW is 'index' and !QR.cooldown.auto and Conf['Open Post in New Tab'] # replying from the index
      Build.path g.BOARD.ID, threadID, postID
    if URL
      if Conf['Open Post in New Tab']
        $.open URL
      else
        window.location = URL

    QR.status()

  abort: ->
    if QR.req and !QR.req.isUploadFinished
      QR.req.abort()
      delete QR.req
      QR.posts[0].unlock()
      QR.cooldown.auto = false
      QR.notifications.push new Notice 'info', 'QR upload aborted.', 5
    QR.status()
