# Weld Service 🔗

## Summary
This service was created originally for [Free Build](https://www.roblox.com/games/4811583863/) for the then upcoming [deprecation of SurfaceTypes](https://devforum.roblox.com/t/changes-to-part-surfaces/334420). This change would also remove the MakeJoints and BreakJoints APIs which are critical for [Free Build](https://www.roblox.com/games/4811583863/) to function therefore, this service was created to provide a replacement for these APIs.
Weld Service is being publicly released now so that others can easily gain access to methods like that of the old APIs. Hopefully with the contribution of others, this service can become an almost drop in replacement for the old APIs which developers can rely on to be performant, reliable & scalable.

## Notes

### Performance
This service has had a focus on optimisation however there is still more to be done & I'm open to suggestions for how to improve performance. I aim to have performance as one of the primary focuses for this service as was originally designed for [Free Build](https://www.roblox.com/games/4811583863/) where servers can have tens of thousands of welded objects.

### Welding Specific Surfaces
The ability to select which surfaces can be welded is not replaced as this service checks all sides of the object. I do however hope to add the ability to specify which surfaces can be welded to in the future & any help towards this is greatly appreciated.

## Finishing Up
With all of that said, I hope you can find use in this module!
Huge thank you to those who contribute!