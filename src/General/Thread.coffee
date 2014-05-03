class Thread
  @callbacks = []
  toString: -> @ID

  constructor: (@ID, @board) ->
    @fullID    = "#{@board}.#{@ID}"
    @posts     = {}
    @isDead    = false
    @isHidden  = false
    @isOnTop   = false
    @isPinned  = false
    @isSticky  = false
    @isClosed  = false
    @postLimit = false
    @fileLimit = false

    @OP = null
    @catalogView = null

    g.threads[@fullID] = board.threads[@] = @

  setStatus: (type, status) ->
    name = "is#{type}"
    return if @[name] is status
    @[name] = status
    return unless @OP
    typeLC = type.toLowerCase()
    unless status
      $.rm $ ".#{typeLC}Icon", @OP.nodes.info
      $.rm $ ".#{typeLC}Icon", @catalogView.nodes.icons if @catalogView
      return

    icon = $.el 'img',
      src: "#{Build.staticPath}#{typeLC}#{Build.gifIcon}"
      title: type
      className: "#{typeLC}Icon"
    root = if type is 'Closed' and @isSticky
      $ '.stickyIcon', @OP.nodes.info
    else if g.VIEW is 'index'
      $ '.page-num', @OP.nodes.info
    else
      $ '[title="Reply to this post"]', @OP.nodes.info
    $.after root, [$.tn(' '), icon]

    return unless @catalogView
    (if type is 'Sticky' and @isClosed then $.prepend else $.add) @catalogView.nodes.icons, icon.cloneNode()

  pin: ->
    @isPinned = true
    $.addClass @catalogView.nodes.root, 'pinned' if @catalogView
  unpin: ->
    @isPinned = false
    $.rmClass  @catalogView.nodes.root, 'pinned' if @catalogView

  hide: ->
    return if @isHidden
    @isHidden = true
    if button = $ '.hide-post-button', @OP.nodes.root
      $.replace button, PostHiding.makeButton false
  show: ->
    return if !@isHidden
    @isHidden = false
    if button = $ '.show-post-button', @OP.nodes.root
      $.replace button, PostHiding.makeButton true

  kill: ->
    @isDead = true

  collect: ->
    for postID, post of @posts
      post.collect()
    delete g.threads[@fullID]
    delete @board.threads[@]
