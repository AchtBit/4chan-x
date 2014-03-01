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
      $ '[title="Quote this post"]', @OP.nodes.info
    $.after root, [$.tn(' '), icon]

    return unless @catalogView
    (if type is 'Sticky' and @isClosed then $.prepend else $.add) @catalogView.nodes.icons, icon.cloneNode()

  pin: ->
    @isPinned = true
    $.addClass @catalogView.nodes.root, 'pinned' if @catalogView
  unpin: ->
    @isPinned = false
    $.rmClass  @catalogView.nodes.root, 'pinned' if @catalogView

  hide: (makeStub=Conf['Stubs']) ->
    return if @isHidden
    @isHidden = true
    root = @OP.nodes.root.parentNode
    Index.updateHideLabel()
    $.rm @catalogView.nodes.root if @catalogView

    unless makeStub
      root.hidden = true
      return

    @stub = $.el 'div',
      className: 'stub'
    {replies} = Index.liveThreadData[Index.liveThreadIDs.indexOf @ID]
    $.add @stub, [
      PostHiding.makeButton false
      $.tn " #{@OP.getNameBlock()} (#{replies} repl#{if replies is 1 then 'y' else 'ies'})"
    ]
    $.add @stub, Menu.makeButton() if Conf['Menu']
    $.prepend root, @stub
  show: ->
    return if !@isHidden
    @isHidden = false
    if @stub
      $.rm @stub
      delete @stub
    @OP.nodes.root.parentNode.hidden = false
    Index.updateHideLabel()
    $.rm @catalogView.nodes.root if @catalogView

  kill: ->
    @isDead = true

  collect: ->
    for postID, post of @posts
      post.collect()
    delete g.threads[@fullID]
    delete @board.threads[@]
