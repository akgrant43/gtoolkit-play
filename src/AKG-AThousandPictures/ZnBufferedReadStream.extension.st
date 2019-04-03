Extension { #name : #ZnBufferedReadStream }

{ #category : #'*AKG-AThousandPictures' }
ZnBufferedReadStream >> savingPositionDo: block [
	"Execute block so that any reading from me in it has no effect afterwards. I remember the current #position and move back to it using #position: after evaluating block. My buffer size limits how long the excursion can be. A SubscriptOutOfBounds exception will be signalled in case this operation cannot be completed."
	
	| savedPosition |
	savedPosition := self position.
	^ block ensure: [ self position: savedPosition ]
]

{ #category : #'*AKG-AThousandPictures' }
ZnBufferedReadStream >> upToEnd [
	"Read elements until the stream is atEnd and return them as a collection."

	| streamSize result |

	"If the stream knows its size we can reduce overhead by allocating a buffer of the correct size"
	streamSize := [ self size ]
		on: Error
		do: [ 0 ].
	streamSize > 0 ifTrue:
		[ result := self next: (streamSize - self position) ].
	"Some streams may only have an estimate, so if not at the end, get the rest"
	self atEnd ifFalse:
		[ result := self collectionSpecies streamContents: [ :out | 
			result ifNotNil: [ out nextPutAll: result ].
			[ self atEnd ] whileFalse: [ 
				position > limit
					ifTrue: [ self nextBuffer ].	
				out next: limit - position + 1 putAll: buffer startingAt: position.
				position := limit + 1 ] ] ].
	^result
]
